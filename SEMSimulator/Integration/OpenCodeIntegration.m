#import "OpenCodeIntegration.h"
#import "KeychainStore.h"

NSString * const SEMOpenCodeDefaultURL = @"http://127.0.0.1:4096";
NSString * const SEMOpenCodeURLDefaultsKey = @"OpenCodeServerURL";
NSString * const SEMOpenCodeModelDefaultsKey = @"OpenCodeModel";
NSString * const SEMOpenCodeKeychainService = @"com.semsimulator.opencode";
NSString * const SEMOpenCodeKeychainAccount = @"password";

static NSString * const SEMOpenCodeErrorDomain = @"SEM.OpenCode";

@implementation OpenCodeIntegration

+ (NSString *)serverURL {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    return [self normalizedURLString:stored ?: SEMOpenCodeDefaultURL];
}

+ (void)setServerURL:(NSString *)url {
    NSString *normalized = [self normalizedURLString:url];
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:SEMOpenCodeURLDefaultsKey];
}

+ (NSString *)configuredModel {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeModelDefaultsKey];
    NSString *trimmed = [stored stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

+ (void)setConfiguredModel:(NSString *)model {
    NSString *trimmed = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (trimmed.length == 0) {
        [defaults removeObjectForKey:SEMOpenCodeModelDefaultsKey];
    } else {
        [defaults setObject:trimmed forKey:SEMOpenCodeModelDefaultsKey];
    }
}

+ (NSString *)password {
    return [KeychainStore stringForService:SEMOpenCodeKeychainService
                                   account:SEMOpenCodeKeychainAccount
                                     error:NULL];
}

+ (BOOL)setPassword:(nullable NSString *)password error:(NSError **)error {
    NSString *trimmed = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) trimmed = nil;
    return [KeychainStore setString:trimmed
                         forService:SEMOpenCodeKeychainService
                            account:SEMOpenCodeKeychainAccount
                              error:error];
}

+ (BOOL)hasPassword {
    return self.password.length > 0;
}

+ (NSString *)effectivePassword {
    // An empty password is intentional: it disables Authorization headers so
    // the app works with an OpenCode server that has no password configured.
    return [self password] ?: @"";
}

+ (NSString *)normalizedURLString:(NSString *)url {
    NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return SEMOpenCodeDefaultURL;
    if ([trimmed rangeOfString:@"://"].location == NSNotFound) {
        trimmed = [@"http://" stringByAppendingString:trimmed];
    }
    while (trimmed.length > 1 && [trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    return trimmed;
}

+ (NSString *)basicAuthorizationForPassword:(NSString *)password {
    NSString *credentials = [NSString stringWithFormat:@"opencode:%@", password ?: @""];
    NSData *data = [credentials dataUsingEncoding:NSUTF8StringEncoding];
    return [@"Basic " stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}

+ (nullable NSURL *)URLForPath:(NSString *)path baseURL:(NSString *)baseURL {
    NSURL *base = [NSURL URLWithString:baseURL];
    if (!base) return nil;
    return [base URLByAppendingPathComponent:path];
}

+ (NSError *)errorWithStatus:(NSInteger)status
                         json:(nullable NSDictionary *)json
                     fallback:(NSString *)fallback {
    NSInteger effectiveStatus = status;
    id jsonStatus = json[@"status"];
    if ([jsonStatus respondsToSelector:@selector(integerValue)]) {
        effectiveStatus = [jsonStatus integerValue];
    }

    NSString *message = [json[@"message"] isKindOfClass:[NSString class]] ? json[@"message"] : nil;
    if (effectiveStatus == 401 || effectiveStatus == 403) {
        message = @"OpenCode authentication failed. Check the password or API key in Settings.";
    } else if (message.length == 0) {
        message = fallback;
    }
    if (effectiveStatus == 429 && message.length > 0) {
        message = [message stringByAppendingString:@" Retry later or choose a local model in Settings."];
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = message.length > 0 ? message : @"OpenCode request failed.";
    if (effectiveStatus > 0) info[@"HTTPStatus"] = @(effectiveStatus);
    return [NSError errorWithDomain:SEMOpenCodeErrorDomain
                               code:effectiveStatus > 0 ? effectiveStatus : 1
                           userInfo:info];
}

+ (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:SEMOpenCodeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (void)requestJSONAtURL:(NSURL *)url
                  method:(NSString *)method
                    body:(nullable NSDictionary *)body
                 timeout:(NSTimeInterval)timeout
              completion:(void (^)(NSInteger status, NSDictionary * _Nullable json, NSError * _Nullable error))completion {
    [self requestJSONAtURL:url
                    method:method
                      body:body
                   timeout:timeout
                  password:[self effectivePassword]
                completion:completion];
}

+ (void)requestJSONAtURL:(NSURL *)url
                  method:(NSString *)method
                    body:(nullable NSDictionary *)body
                 timeout:(NSTimeInterval)timeout
                password:(nullable NSString *)password
              completion:(void (^)(NSInteger status, NSDictionary * _Nullable json, NSError * _Nullable error))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = timeout;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    if (password.length > 0) {
        [request setValue:[self basicAuthorizationForPassword:password] forHTTPHeaderField:@"Authorization"];
    }

    if (body) {
        NSError *encodingError = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encodingError];
        if (!request.HTTPBody) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(0, nil, encodingError);
            });
            return;
        }
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([object isKindOfClass:[NSDictionary class]]) json = object;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(status, json, error);
        });
    }];
    [task resume];
}

+ (nullable NSDictionary *)modelReferenceFromString:(NSString *)model {
    NSString *trimmed = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange slash = [trimmed rangeOfString:@"/"];
    if (slash.location == NSNotFound || slash.location == 0 || slash.location + 1 >= trimmed.length) {
        return nil;
    }
    NSString *providerID = [trimmed substringToIndex:slash.location];
    NSString *modelID = [trimmed substringFromIndex:slash.location + 1];
    if (providerID.length == 0 || modelID.length == 0) return nil;
    return @{ @"providerID": providerID, @"id": modelID };
}

+ (NSInteger)localProviderPriority:(NSString *)providerID {
    NSString *provider = providerID.lowercaseString;
    if ([provider isEqualToString:@"ollama"]) return 0;
    if ([provider isEqualToString:@"llamacpp"] || [provider isEqualToString:@"llama.cpp"]) return 1;
    if ([provider isEqualToString:@"lmstudio"]) return 2;
    if ([provider isEqualToString:@"local"]) return 3;
    return NSIntegerMax;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)modelCandidatesFromJSON:(NSDictionary *)json {
    NSArray *models = [json[@"data"] isKindOfClass:[NSArray class]] ? json[@"data"] : nil;
    NSMutableArray<NSDictionary<NSString *, id> *> *candidates = [NSMutableArray array];
    for (NSDictionary *model in models) {
        if (![model isKindOfClass:[NSDictionary class]]) continue;
        id enabled = model[@"enabled"];
        if ([enabled respondsToSelector:@selector(boolValue)] && ![enabled boolValue]) continue;
        NSString *type = [model[@"type"] isKindOfClass:[NSString class]] ? model[@"type"] : nil;
        if (type.length > 0 && ![type isEqualToString:@"chat"]) continue;

        NSString *providerID = [model[@"providerID"] isKindOfClass:[NSString class]] ? model[@"providerID"] : nil;
        NSString *modelID = [model[@"id"] isKindOfClass:[NSString class]] ? model[@"id"] : nil;
        if (modelID.length == 0 && [model[@"modelID"] isKindOfClass:[NSString class]]) modelID = model[@"modelID"];
        if (providerID.length == 0 || modelID.length == 0) continue;

        NSInteger score = 20;
        NSInteger localPriority = [self localProviderPriority:providerID];
        BOOL local = localPriority != NSIntegerMax;
        BOOL freeModel = [providerID.lowercaseString isEqualToString:@"opencode"] || [modelID.lowercaseString hasSuffix:@"-free"];
        if (local) {
            score = localPriority;
        } else if (freeModel) {
            score = 10;
        }

        [candidates addObject:@{
            @"identifier": [NSString stringWithFormat:@"%@/%@", providerID, modelID],
            @"providerID": providerID,
            @"modelID": modelID,
            @"score": @(score),
            @"order": @(candidates.count),
            @"local": @(local),
            @"free": @(freeModel),
            @"name": [model[@"name"] isKindOfClass:[NSString class]] ? model[@"name"] : modelID
        }];
    }

    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger scoreA = [a[@"score"] integerValue];
        NSInteger scoreB = [b[@"score"] integerValue];
        if (scoreA != scoreB) return scoreA < scoreB ? NSOrderedAscending : NSOrderedDescending;
        NSInteger orderA = [a[@"order"] integerValue];
        NSInteger orderB = [b[@"order"] integerValue];
        if (orderA != orderB) return orderA < orderB ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return candidates;
}

+ (void)fetchAvailableModelsForURL:(NSString *)url
                          password:(nullable NSString *)password
                        completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> * _Nullable,
                                             NSError * _Nullable))completion {
    NSString *baseURL = [self normalizedURLString:url];
    NSURL *modelURL = [self URLForPath:@"api/model" baseURL:baseURL];
    if (!modelURL) {
        completion(nil, [self errorWithMessage:@"Invalid OpenCode server URL." code:400]);
        return;
    }

    [self requestJSONAtURL:modelURL
                    method:@"GET"
                      body:nil
                   timeout:10.0
                  password:password
                completion:^(NSInteger status, NSDictionary *json, NSError *error) {
        if (error) {
            completion(nil, [self errorWithMessage:[NSString stringWithFormat:@"Could not list OpenCode models: %@", error.localizedDescription]
                                              code:error.code]);
            return;
        }
        if (status != 200) {
            completion(nil, [self errorWithStatus:status json:json fallback:@"Could not list OpenCode models."]);
            return;
        }
        completion([self modelCandidatesFromJSON:json ?: @{}], nil);
    }];
}

+ (void)fetchAvailableModelsWithCompletion:(void (^)(NSArray<NSDictionary<NSString *, id> *> * _Nullable,
                                                     NSError * _Nullable))completion {
    [self fetchAvailableModelsForURL:[self serverURL]
                            password:[self effectivePassword]
                          completion:completion];
}

+ (void)resolveModelWithCompletion:(void (^)(NSString * _Nullable model, NSError * _Nullable error))completion {
    NSString *configured = [self configuredModel];
    if (configured.length > 0) {
        completion(configured, nil);
        return;
    }

    [self fetchAvailableModelsWithCompletion:^(NSArray<NSDictionary<NSString *, id> *> *models, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSDictionary *best = models.firstObject;
        if (!best) {
            completion(nil, [self errorWithMessage:@"No OpenCode chat model is available. Choose a model in Settings or start a local model server."
                                              code:404]);
            return;
        }
        completion(best[@"identifier"], nil);
    }];
}

+ (void)performGenerateTextWithPrompt:(NSString *)prompt
                       modelReference:(nullable NSDictionary *)modelReference
                           completion:(void (^)(NSString * _Nullable text,
                                                NSInteger status,
                                                NSError * _Nullable error))completion {
    NSString *baseURL = [self serverURL];
    NSURL *url = [self URLForPath:@"api/experimental/generate/text" baseURL:baseURL];
    if (!url) {
        completion(nil, 0, [self errorWithMessage:@"Invalid OpenCode server URL." code:400]);
        return;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:prompt forKey:@"prompt"];
    if (modelReference) payload[@"model"] = modelReference;

    [self requestJSONAtURL:url method:@"POST" body:payload timeout:120.0
                completion:^(NSInteger status, NSDictionary *json, NSError *error) {
        if (error) {
            completion(nil, status, [self errorWithMessage:[NSString stringWithFormat:@"OpenCode request failed: %@", error.localizedDescription]
                                                      code:error.code]);
            return;
        }
        if (status != 200) {
            completion(nil, status, [self errorWithStatus:status json:json fallback:[NSString stringWithFormat:@"OpenCode returned HTTP %ld.", (long)status]]);
            return;
        }

        NSDictionary *data = [json[@"data"] isKindOfClass:[NSDictionary class]] ? json[@"data"] : nil;
        NSString *text = [data[@"text"] isKindOfClass:[NSString class]] ? data[@"text"] : nil;
        if (text.length == 0) {
            completion(nil, status, [self errorWithMessage:@"OpenCode returned an empty response." code:204]);
            return;
        }
        completion(text, status, nil);
    }];
}

+ (void)generateTextWithPrompt:(NSString *)prompt
                         model:(NSString *)model
                    completion:(void (^)(NSString * _Nullable text,
                                         NSInteger status,
                                         NSError * _Nullable error))completion {
    NSString *trimmedPrompt = [prompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedPrompt.length == 0) {
        completion(nil, 0, [self errorWithMessage:@"The generation prompt is empty." code:400]);
        return;
    }

    NSString *selected = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (selected.length == 0) selected = [self configuredModel];

    if (selected.length > 0) {
        NSDictionary *reference = [self modelReferenceFromString:selected];
        if (!reference) {
            completion(nil, 0, [self errorWithMessage:@"The OpenCode model must use the provider/model format, for example ollama/llama3.2:3b." code:400]);
            return;
        }
        [self performGenerateTextWithPrompt:trimmedPrompt modelReference:reference completion:completion];
        return;
    }

    [self resolveModelWithCompletion:^(NSString *resolved, NSError *error) {
        if (resolved.length == 0) {
            completion(nil, 0, error);
            return;
        }
        NSDictionary *reference = [self modelReferenceFromString:resolved];
        if (!reference) {
            completion(nil, 0, [self errorWithMessage:@"Could not resolve an OpenCode model. Set provider/model in Settings." code:400]);
            return;
        }
        [self performGenerateTextWithPrompt:trimmedPrompt modelReference:reference completion:completion];
    }];
}

+ (void)finishTestForURL:(NSString *)baseURL
                  status:(NSInteger)status
                    json:(NSDictionary *)json
                   error:(NSError *)error
              completion:(void (^)(BOOL ok, NSString *message))completion {
    if (error) {
        completion(NO, [NSString stringWithFormat:@"Could not reach %@: %@", baseURL, error.localizedDescription]);
        return;
    }
    if (status == 200) {
        NSString *version = [json[@"version"] isKindOfClass:[NSString class]] ? json[@"version"] : nil;
        if (version.length > 0) {
            completion(YES, [NSString stringWithFormat:@"Connected to OpenCode %@ at %@", version, baseURL]);
        } else {
            completion(YES, [NSString stringWithFormat:@"OpenCode server responded at %@", baseURL]);
        }
        return;
    }
    if (status == 401 || status == 403) {
        completion(NO, @"Authentication failed. Check the OpenCode password or API key.");
        return;
    }
    if (status == 0) {
        completion(NO, [NSString stringWithFormat:@"No response from %@", baseURL]);
        return;
    }
    completion(NO, [NSString stringWithFormat:@"OpenCode returned HTTP %ld from %@", (long)status, baseURL]);
}

+ (void)requestInfoAtURL:(NSURL *)url
           authorization:(nullable NSString *)authorization
              completion:(void (^)(NSInteger status, NSDictionary * _Nullable json, NSError * _Nullable error))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 6.0;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (authorization.length > 0) {
        [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([object isKindOfClass:[NSDictionary class]]) json = object;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(status, json, error);
        });
    }];
    [task resume];
}

+ (void)testServerURL:(NSString *)url
             password:(nullable NSString *)password
           completion:(void (^)(BOOL ok, NSString *message))completion {
    NSString *baseURL = [self normalizedURLString:url];
    NSURL *infoURL = [self URLForPath:@"api/info" baseURL:baseURL];
    if (!infoURL) {
        completion(NO, @"Invalid OpenCode server URL.");
        return;
    }

    NSString *authorization = password.length > 0 ? [self basicAuthorizationForPassword:password] : nil;
    [self requestInfoAtURL:infoURL authorization:authorization completion:^(NSInteger status, NSDictionary *json, NSError *error) {
        if (status == 401 && password.length > 0) {
            NSString *bearer = [@"Bearer " stringByAppendingString:password];
            [self requestInfoAtURL:infoURL authorization:bearer completion:^(NSInteger bearerStatus, NSDictionary *bearerJSON, NSError *bearerError) {
                [self finishTestForURL:baseURL status:bearerStatus json:bearerJSON error:bearerError completion:completion];
            }];
            return;
        }
        [self finishTestForURL:baseURL status:status json:json error:error completion:completion];
    }];
}

@end
