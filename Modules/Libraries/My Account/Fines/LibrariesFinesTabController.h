#import <Foundation/Foundation.h>
#import "LibrariesFinesSummaryView.h"

@interface LibrariesFinesTabController : NSObject <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic,assign) UIViewController *parentController;
@property (nonatomic,retain) UITableView *tableView;
@property (nonatomic,retain) LibrariesFinesSummaryView* headerView;

- (id)initWithTableView:(UITableView*)tableView;

- (void)tabWillBecomeActive;
- (void)tabDidBecomeActive;
- (void)tabWillBecomeInactive;
- (void)tabDidBecomeInactive;

@end
