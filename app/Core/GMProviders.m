// GM Agent · 供应商预设（内置常用 + 自定义）
#import "GMProviders.h"

@implementation GMProviderPreset

+ (instancetype)make:(NSString *)ident
               title:(NSString *)title
                 url:(NSString *)url
              models:(NSArray<NSString *> *)models
                hint:(NSString *)hint {
    GMProviderPreset *p = [GMProviderPreset new];
    p.identifier = ident;
    p.title = title;
    p.baseURL = url;
    p.models = models;
    p.defaultModel = models.firstObject ?: @"";
    p.keyHint = hint;
    return p;
}

+ (NSArray<GMProviderPreset *> *)all {
    static NSArray *arr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        arr = @[
            [self make:@"deepseek" title:@"DeepSeek"
                  url:@"https://api.deepseek.com/v1/chat/completions"
               models:@[@"deepseek-chat", @"deepseek-reasoner"]
                 hint:@"platform.deepseek.com"],
            [self make:@"openai" title:@"OpenAI"
                  url:@"https://api.openai.com/v1/chat/completions"
               models:@[@"gpt-5.2", @"gpt-5.1", @"gpt-4.1", @"gpt-4o"]
                 hint:@"platform.openai.com"],
            [self make:@"gemini" title:@"Google Gemini（OpenAI 兼容）"
                  url:@"https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
               models:@[@"gemini-2.5-pro", @"gemini-2.5-flash"]
                 hint:@"aistudio.google.com"],
            [self make:@"moonshot" title:@"Moonshot 月之暗面"
                  url:@"https://api.moonshot.cn/v1/chat/completions"
               models:@[@"kimi-k2-0905-preview", @"moonshot-v1-128k"]
                 hint:@"platform.moonshot.cn"],
            [self make:@"zhipu" title:@"智谱 GLM"
                  url:@"https://open.bigmodel.cn/api/paas/v4/chat/completions"
               models:@[@"glm-4.6", @"glm-4-plus"]
                 hint:@"open.bigmodel.cn"],
            [self make:@"dashscope" title:@"阿里通义（DashScope）"
                  url:@"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
               models:@[@"qwen3-max", @"qwen-plus"]
                 hint:@"dashscope.console.aliyun.com"],
            [self make:@"openrouter" title:@"OpenRouter"
                  url:@"https://openrouter.ai/api/v1/chat/completions"
               models:@[@"anthropic/claude-sonnet-4.5", @"openai/gpt-5.2", @"deepseek/deepseek-chat"]
                 hint:@"openrouter.ai/keys"],
            [self make:@"custom" title:@"自定义（OpenAI 兼容）"
                  url:@"https://"
               models:@[@"gpt-5.2"]
                 hint:@"填完整的 /chat/completions 地址"],
        ];
    });
    return arr;
}

+ (GMProviderPreset *)presetForIdentifier:(NSString *)ident {
    if (!ident.length) return [self all].firstObject;
    for (GMProviderPreset *p in [self all])
        if ([p.identifier isEqualToString:ident]) return p;
    return [self all].lastObject;
}

@end
