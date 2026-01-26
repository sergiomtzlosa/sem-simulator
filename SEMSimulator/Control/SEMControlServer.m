#import "SEMControlServer.h"

#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>

NSString * const SEMControlErrorDomain = @"SEM.Control";

NSError *SEMControlMakeError(SEMControlErrorCode code, NSString *message) {
    return [NSError errorWithDomain:SEMControlErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"SEM control error"}];
}

static const NSUInteger SEMControlMaxRequestBytes = 1024 * 1024;
static const NSTimeInterval SEMControlSampleTimeout = 120.0;
static const NSTimeInterval SEMControlSocketTimeout = 8.0;

@interface SEMHTTPRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, strong) NSData *body;
@end

@implementation SEMHTTPRequest
@end

@interface SEMControlServer ()
@property (nonatomic, readwrite) uint16_t port;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@end

@implementation SEMControlServer {
    int _listenFD;
    dispatch_queue_t _acceptQueue;
    dispatch_queue_t _connectionQueue;
    dispatch_source_t _acceptSource;
    NSString *_authToken;
}

- (instancetype)initWithDelegate:(id<SEMControlServerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _listenFD = -1;
        _authToken = [NSProcessInfo.processInfo.environment[@"SEM_CONTROL_TOKEN"] copy];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Lifecycle

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    if (self.running) return YES;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"socket: %s", strerror(errno)]}];
        return NO;
    }

    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int savedErrno = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not bind 127.0.0.1:%u: %s", port, strerror(savedErrno)]}];
        return NO;
    }

    if (listen(fd, 16) != 0) {
        int savedErrno = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"listen: %s", strerror(savedErrno)]}];
        return NO;
    }

    socklen_t length = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &length) == 0) {
        self.port = ntohs(address.sin_port);
    } else {
        self.port = port;
    }

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    _listenFD = fd;
    _acceptQueue = dispatch_queue_create("com.semsimulator.control.accept", DISPATCH_QUEUE_SERIAL);
    _connectionQueue = dispatch_queue_create("com.semsimulator.control.connections", DISPATCH_QUEUE_CONCURRENT);

    int listenFD = fd;
    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _acceptQueue);
    if (!_acceptSource) {
        close(fd);
        _listenFD = -1;
        if (error) *error = SEMControlMakeError(SEMControlErrorInternal, @"Could not create control listener.");
        return NO;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_acceptSource, ^{
        [weakSelf acceptPendingConnections];
    });
    dispatch_source_set_cancel_handler(_acceptSource, ^{
        close(listenFD);
    });
    dispatch_resume(_acceptSource);

    self.running = YES;
    return YES;
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    if (_acceptSource) {
        dispatch_source_cancel(_acceptSource);
        _acceptSource = nil;
    }
    _listenFD = -1;
}

#pragma mark - Accepting connections

- (void)acceptPendingConnections {
    if (!self.running || _listenFD < 0) return;

    while (1) {
        int client = accept(_listenFD, NULL, NULL);
        if (client < 0) break;

        int yes = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));

        int flags = fcntl(client, F_GETFL, 0);
        if (flags >= 0) fcntl(client, F_SETFL, flags & ~O_NONBLOCK);

        struct timeval timeout;
        timeout.tv_sec = (time_t)SEMControlSocketTimeout;
        timeout.tv_usec = 0;
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        __weak typeof(self) weakSelf = self;
        dispatch_async(_connectionQueue, ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                close(client);
                return;
            }
            [self handleClient:client];
        });
    }
}

- (void)handleClient:(int)client {
    @autoreleasepool {
        SEMHTTPRequest *request = [self readRequestFromSocket:client];
        if (!request) {
            [self sendJSON:@{@"ok": @NO, @"error": @"Malformed HTTP request."} status:400 client:client];
        } else {
            [self processRequest:request client:client];
        }
        shutdown(client, SHUT_WR);
        close(client);
    }
}

#pragma mark - HTTP parsing

- (nullable SEMHTTPRequest *)readRequestFromSocket:(int)client {
    NSMutableData *data = [NSMutableData data];
    NSData *marker = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    char buffer[4096];
    NSUInteger headerEnd = NSNotFound;

    while (data.length <= SEMControlMaxRequestBytes) {
        NSRange found = [data rangeOfData:marker options:0 range:NSMakeRange(0, data.length)];
        if (found.location != NSNotFound) {
            headerEnd = NSMaxRange(found);
            break;
        }
        ssize_t count = recv(client, buffer, sizeof(buffer), 0);
        if (count <= 0) return nil;
        [data appendBytes:buffer length:(NSUInteger)count];
    }

    if (headerEnd == NSNotFound || headerEnd < marker.length) return nil;

    NSData *headerData = [data subdataWithRange:NSMakeRange(0, headerEnd - marker.length)];
    NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    if (headerText.length == 0) return nil;

    NSString *normalized = [headerText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
    if (lines.count == 0) return nil;

    NSArray<NSString *> *requestParts = [self nonEmptyComponents:lines.firstObject];
    if (requestParts.count < 3) return nil;

    SEMHTTPRequest *request = [[SEMHTTPRequest alloc] init];
    request.method = requestParts[0].uppercaseString;
    request.path = [self normalizedPath:requestParts[1]];

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger index = 1; index < lines.count; index++) {
        NSString *line = lines[index];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (key.length > 0) headers[key] = value;
    }
    request.headers = headers;

    NSUInteger contentLength = (NSUInteger)MAX(0LL, [headers[@"content-length"] longLongValue]);
    if (contentLength > SEMControlMaxRequestBytes) return nil;

    NSUInteger expectedLength = headerEnd + contentLength;
    while (data.length < expectedLength) {
        ssize_t count = recv(client, buffer, sizeof(buffer), 0);
        if (count <= 0) return nil;
        [data appendBytes:buffer length:(NSUInteger)count];
        if (data.length > SEMControlMaxRequestBytes) return nil;
    }

    request.body = contentLength > 0 ? [data subdataWithRange:NSMakeRange(headerEnd, contentLength)] : [NSData data];
    return request;
}

- (NSArray<NSString *> *)nonEmptyComponents:(NSString *)line {
    NSArray<NSString *> *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [result addObject:part];
    }
    return result;
}

- (NSString *)normalizedPath:(NSString *)path {
    NSRange query = [path rangeOfString:@"?"];
    if (query.location != NSNotFound) path = [path substringToIndex:query.location];
    if (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    return path;
}

#pragma mark - Routing

- (void)processRequest:(SEMHTTPRequest *)request client:(int)client {
    NSString *method = request.method;
    NSString *path = request.path;

    if ([method isEqualToString:@"OPTIONS"]) {
        [self sendOptions:client];
        return;
    }

    if (![self isAuthorized:request]) {
        [self sendJSON:@{@"ok": @NO, @"error": @"Unauthorized. Set SEM_CONTROL_TOKEN and send a Bearer token."} status:401 client:client];
        return;
    }

    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/health"]) {
        [self sendJSON:@{@"ok": @YES, @"app": @"SEM Simulator", @"controlApi": @1} status:200 client:client];
        return;
    }

    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/status"]) {
        [self handleStatus:client];
        return;
    }

    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/sample"]) {
        [self handleSample:request client:client];
        return;
    }

    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/vacuum"]) {
        [self handleVacuum:request client:client];
        return;
    }

    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/imaging"]) {
        [self handleImaging:request client:client];
        return;
    }

    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/"]) {
        [self sendJSON:@{
            @"ok": @YES,
            @"app": @"SEM Simulator",
            @"controlApi": @1,
            @"endpoints": @{
                @"GET /health": @"Liveness check.",
                @"GET /status": @"Chamber, beam, optics, and specimen status.",
                @"POST /sample": @"Generate a specimen. JSON: {prompt, variation?, load?, gold_coat?}.",
                @"POST /vacuum": @"Vacuum action. JSON: {action: evac|vent|reset_fault}.",
                @"POST /imaging": @"Imaging state. JSON: {hv?: bool, gold_coat?: bool}."
            }
        } status:200 client:client];
        return;
    }

    BOOL knownPath = [path isEqualToString:@"/health"] || [path isEqualToString:@"/status"] || [path isEqualToString:@"/sample"] || [path isEqualToString:@"/vacuum"] || [path isEqualToString:@"/imaging"];
    if (knownPath) {
        [self sendJSON:@{@"ok": @NO, @"error": [NSString stringWithFormat:@"Method %@ is not allowed for %@.", method, path]} status:405 client:client];
    } else {
        [self sendJSON:@{@"ok": @NO, @"error": [NSString stringWithFormat:@"Unknown endpoint %@.", path]} status:404 client:client];
    }
}

- (BOOL)isAuthorized:(SEMHTTPRequest *)request {
    if (_authToken.length == 0) return YES;
    NSString *header = request.headers[@"authorization"] ?: @"";
    NSString *expected = [@"Bearer " stringByAppendingString:_authToken];
    if ([header isEqualToString:expected]) return YES;
    return [request.headers[@"x-sem-token"] isEqualToString:_authToken];
}

#pragma mark - Handlers

- (void)handleStatus:(int)client {
    id<SEMControlServerDelegate> delegate = self.delegate;
    if (!delegate) {
        [self sendJSON:@{@"ok": @NO, @"error": @"SEM Simulator is not ready."} status:503 client:client];
        return;
    }
    __block NSDictionary<NSString *, id> *status = nil;
    [self performOnMain:^{
        status = [delegate statusForControlServer:self];
    }];
    [self sendJSON:status ?: @{@"ok": @NO, @"error": @"Status unavailable."} status:200 client:client];
}

- (void)handleSample:(SEMHTTPRequest *)request client:(int)client {
    NSString *message = nil;
    NSDictionary<NSString *, id> *body = [self JSONBodyForRequest:request errorMessage:&message];
    if (!body) {
        [self sendJSON:@{@"ok": @NO, @"error": message ?: @"Invalid JSON body."} status:400 client:client];
        return;
    }

    id promptValue = body[@"prompt"];
    if (![promptValue isKindOfClass:[NSString class]]) {
        [self sendJSON:@{@"ok": @NO, @"error": @"The prompt field is required and must be a string."} status:400 client:client];
        return;
    }
    NSString *prompt = [(NSString *)promptValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (prompt.length == 0 || prompt.length > 500) {
        [self sendJSON:@{@"ok": @NO, @"error": @"The prompt must contain 1-500 characters."} status:400 client:client];
        return;
    }

    NSUInteger variation = body[@"variation"] ? (NSUInteger)[body[@"variation"] unsignedLongLongValue] : (NSUInteger)arc4random();
    BOOL load = body[@"load"] ? [body[@"load"] boolValue] : YES;
    BOOL goldCoat = NO;
    if (body[@"gold_coat"]) goldCoat = [body[@"gold_coat"] boolValue];
    else if (body[@"goldCoat"]) goldCoat = [body[@"goldCoat"] boolValue];

    id<SEMControlServerDelegate> delegate = self.delegate;
    if (!delegate) {
        [self sendJSON:@{@"ok": @NO, @"error": @"SEM Simulator is not ready."} status:503 client:client];
        return;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary<NSString *, id> *result = nil;
    __block NSError *error = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate controlServer:self
             setSampleWithPrompt:prompt
                       variation:variation
                            load:load
                        goldCoat:goldCoat
                      completion:^(NSDictionary<NSString *, id> * _Nullable sampleResult, NSError * _Nullable sampleError) {
            result = sampleResult;
            error = sampleError;
            dispatch_semaphore_signal(semaphore);
        }];
    });

    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SEMControlSampleTimeout * NSEC_PER_SEC)));
    if (waitResult != 0) {
        [self sendJSON:@{@"ok": @NO, @"error": @"Timed out waiting for specimen generation/loading."} status:504 client:client];
        return;
    }
    if (error) {
        [self sendError:error client:client];
        return;
    }
    [self sendJSON:result ?: @{@"ok": @YES} status:200 client:client];
}

- (void)handleVacuum:(SEMHTTPRequest *)request client:(int)client {
    NSString *message = nil;
    NSDictionary<NSString *, id> *body = [self JSONBodyForRequest:request errorMessage:&message];
    if (!body) {
        [self sendJSON:@{@"ok": @NO, @"error": message ?: @"Invalid JSON body."} status:400 client:client];
        return;
    }
    id actionValue = body[@"action"];
    if (![actionValue isKindOfClass:[NSString class]]) {
        [self sendJSON:@{@"ok": @NO, @"error": @"The action field is required (evac, vent, reset_fault)."} status:400 client:client];
        return;
    }
    NSString *action = [(NSString *)actionValue lowercaseString];

    id<SEMControlServerDelegate> delegate = self.delegate;
    if (!delegate) {
        [self sendJSON:@{@"ok": @NO, @"error": @"SEM Simulator is not ready."} status:503 client:client];
        return;
    }

    __block BOOL success = NO;
    __block NSError *error = nil;
    __block NSDictionary<NSString *, id> *status = nil;
    [self performOnMain:^{
        success = [delegate controlServer:self performVacuumAction:action error:&error];
        status = [delegate statusForControlServer:self];
    }];
    if (!success) {
        [self sendError:error client:client];
        return;
    }
    [self sendJSON:@{@"ok": @YES, @"status": status ?: @{}} status:200 client:client];
}

- (void)handleImaging:(SEMHTTPRequest *)request client:(int)client {
    NSString *message = nil;
    NSDictionary<NSString *, id> *body = [self JSONBodyForRequest:request errorMessage:&message];
    if (!body) {
        [self sendJSON:@{@"ok": @NO, @"error": message ?: @"Invalid JSON body."} status:400 client:client];
        return;
    }

    BOOL hasHV = body[@"hv"] != nil;
    BOOL hasCoating = body[@"gold_coat"] != nil || body[@"goldCoat"] != nil;
    if (!hasHV && !hasCoating) {
        [self sendJSON:@{@"ok": @NO, @"error": @"Provide hv and/or gold_coat."} status:400 client:client];
        return;
    }

    id<SEMControlServerDelegate> delegate = self.delegate;
    if (!delegate) {
        [self sendJSON:@{@"ok": @NO, @"error": @"SEM Simulator is not ready."} status:503 client:client];
        return;
    }

    BOOL hv = body[@"hv"] ? [body[@"hv"] boolValue] : NO;
    BOOL coated = body[@"gold_coat"] ? [body[@"gold_coat"] boolValue] : [body[@"goldCoat"] boolValue];

    __block BOOL success = YES;
    __block NSError *error = nil;
    __block NSDictionary<NSString *, id> *status = nil;
    [self performOnMain:^{
        if (hasHV) success = [delegate controlServer:self setHighVoltage:hv error:&error];
        if (success && hasCoating) success = [delegate controlServer:self setGoldCoated:coated error:&error];
        status = [delegate statusForControlServer:self];
    }];
    if (!success) {
        [self sendError:error client:client];
        return;
    }
    [self sendJSON:@{@"ok": @YES, @"status": status ?: @{}} status:200 client:client];
}

#pragma mark - Helpers

- (nullable NSDictionary<NSString *, id> *)JSONBodyForRequest:(SEMHTTPRequest *)request errorMessage:(NSString **)message {
    if (request.body.length == 0) return @{};
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:&error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (message) *message = @"Request body must be a JSON object.";
        return nil;
    }
    return object;
}

- (void)performOnMain:(dispatch_block_t)block {
    if ([NSThread isMainThread]) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}

- (void)sendError:(NSError *)error client:(int)client {
    NSInteger status = [self HTTPStatusForError:error];
    [self sendJSON:@{@"ok": @NO, @"error": error.localizedDescription ?: @"Control request failed."} status:status client:client];
}

- (NSInteger)HTTPStatusForError:(NSError *)error {
    if (![error.domain isEqualToString:SEMControlErrorDomain]) return 500;
    switch ((SEMControlErrorCode)error.code) {
        case SEMControlErrorInvalidRequest: return 400;
        case SEMControlErrorNotFound: return 404;
        case SEMControlErrorMethodNotAllowed: return 405;
        case SEMControlErrorUnauthorized: return 401;
        case SEMControlErrorInterlock: return 409;
        case SEMControlErrorBusy: return 409;
        case SEMControlErrorTimeout: return 504;
        case SEMControlErrorInternal: return 500;
    }
    return 500;
}

- (void)sendOptions:(int)client {
    NSString *headers =
        @"HTTP/1.1 204 No Content\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        @"Access-Control-Allow-Headers: Content-Type, Authorization, X-SEM-Token\r\n"
        @"Access-Control-Max-Age: 86400\r\n"
        @"Content-Length: 0\r\n"
        @"Connection: close\r\n"
        @"\r\n";
    [self sendData:[headers dataUsingEncoding:NSUTF8StringEncoding] client:client];
}

- (void)sendJSON:(NSDictionary<NSString *, id> *)payload status:(NSInteger)status client:(int)client {
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    if (!body) body = [NSData data];

    NSMutableString *headers = [NSMutableString string];
    [headers appendFormat:@"HTTP/1.1 %ld %@\r\n", (long)status, [self reasonForStatus:status]];
    [headers appendString:@"Content-Type: application/json; charset=utf-8\r\n"];
    [headers appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    [headers appendString:@"Connection: close\r\n"];
    [headers appendString:@"Cache-Control: no-store\r\n"];
    [headers appendString:@"Access-Control-Allow-Origin: *\r\n"];
    [headers appendString:@"\r\n"];

    NSMutableData *response = [NSMutableData dataWithData:[headers dataUsingEncoding:NSUTF8StringEncoding]];
    [response appendData:body];
    [self sendData:response client:client];
}

- (NSString *)reasonForStatus:(NSInteger)status {
    switch (status) {
        case 200: return @"OK";
        case 204: return @"No Content";
        case 400: return @"Bad Request";
        case 401: return @"Unauthorized";
        case 404: return @"Not Found";
        case 405: return @"Method Not Allowed";
        case 409: return @"Conflict";
        case 500: return @"Internal Server Error";
        case 503: return @"Service Unavailable";
        case 504: return @"Gateway Timeout";
    }
    return @"OK";
}

- (void)sendData:(NSData *)data client:(int)client {
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t sent = send(client, bytes, remaining, 0);
        if (sent <= 0) break;
        bytes += sent;
        remaining -= (NSUInteger)sent;
    }
}

@end
