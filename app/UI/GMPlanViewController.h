// GM Agent · 子代理计划视图（进度 / 复核 / 决策）
#import <UIKit/UIKit.h>

@interface GMPlanStep : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger state;   // 0 待办 1 进行中 2 完成 3 失败
@end

@interface GMPlanProgressViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithTask:(NSString *)task steps:(NSArray<GMPlanStep *> *)steps;
- (void)updateSteps:(NSArray<GMPlanStep *> *)steps;
@end

@interface GMPlanReviewViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) void (^onAccept)(void);
@property (nonatomic, copy) void (^onReject)(void);
- (instancetype)initWithTask:(NSString *)task steps:(NSArray<GMPlanStep *> *)steps;
@end

@interface GMPlanDecisionViewController : UIViewController
- (instancetype)initWithTask:(NSString *)task output:(NSString *)output;
@end
