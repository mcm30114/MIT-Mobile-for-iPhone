#import <Foundation/Foundation.h>
#import "LibrariesHoldsSummaryView.h"

@interface LibrariesHoldsTabController : NSObject <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic,assign) UIViewController *parentController;
@property (nonatomic,retain) UITableView *tableView;
@property (nonatomic,retain) LibrariesHoldsSummaryView* headerView;

- (id)initWithTableView:(UITableView*)tableView;

- (void)tabWillBecomeActive;
- (void)tabDidBecomeActive;
- (void)tabWillBecomeInactive;
- (void)tabDidBecomeInactive;
@end
