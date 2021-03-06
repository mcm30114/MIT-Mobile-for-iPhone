#import "LibrariesBookDetailViewController.h"
#import "MobileRequestOperation.h"
#import "MITMobileWebAPI.h"
#import "MITUIConstants.h"
#import "LibrariesModule.h"
#import "Foundation+MITAdditions.h"
#import "BookDetailTableViewCell.h"
#import "WorldCatHoldingsViewController.h"
#import "LibrariesHoldingsDetailViewController.h"

#define TITLE_ROW 0
#define YEAR_AUTHOR_ROW 1
#define ISBN_ROW 2

static const CGFloat kWebViewHeight = 300.0f;

typedef enum 
{
    kInfoSection = 0,
    kEmailAndCiteSection = 1,
    kMITHoldingSection = 2,
    kBLCHoldingSection = 3
}
BookDetailSections;

#define HORIZONTAL_MARGIN 10
#define VERTICAL_PADDING 5
#define HORIZONTAL_PADDING 5

@interface LibrariesBookDetailViewController (Private)
- (void)loadBookDetails;
- (void)updateUI;
- (void)configureCell:(UITableViewCell *)cell 
    forRowAtIndexPath:(NSIndexPath *)indexPath;

@end

@implementation LibrariesBookDetailViewController
@synthesize book;
@synthesize activityView;
@synthesize loadingStatus;
@synthesize bookInfo;

- (id)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        // Custom initialization
        self.title = @"Book Detail";
    }
    return self;
}

- (void)dealloc
{
    self.activityView = nil;
    [super dealloc];
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

/*
// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView
{
}
*/


// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.activityView = [[[MITLoadingActivityView alloc] initWithFrame:self.view.bounds] autorelease];
    self.activityView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.activityView];
    [self loadBookDetails];
}


- (void)viewDidUnload
{
    [super viewDidUnload];
    self.activityView = nil;
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (NSString *)subtitleDisplayStringHTML:(BOOL)isHTML
{
    NSString *result = nil;
    if (self.book) {
        result = @"";
        if (self.book.authors.count) {
            result = [self.book.authors componentsJoinedByString:@", "];
        }
        
        if ([self.book.years count] > 0) {
            result = [NSString stringWithFormat:@"%@; %@", [self.book.years objectAtIndex:0], result]; 
        }
    }
    return result;
}

- (void)loadBookDetails {
    NSDictionary *parameters = [NSDictionary dictionaryWithObject:self.book.identifier forKey:@"id"];
    MobileRequestOperation *request = [[[MobileRequestOperation alloc] initWithModule:LibrariesTag command:@"detail" parameters:parameters] autorelease];
    
    self.loadingStatus = BookLoadingStatusPartial;
    
    request.completeBlock = ^(MobileRequestOperation *operation, id jsonResult, NSError *error) {
        [self.activityView removeFromSuperview];
        
        if (error) {
            [MITMobileWebAPI showErrorWithHeader:@"WorldCat Book Details"];
            self.loadingStatus = BookLoadingStatusFailed;

        } else {
            [self.book updateDetailsWithDictionary:jsonResult];
            
            NSMutableArray *bookAttribs = [NSMutableArray array];
            
            // title, author, format
            NSString *bookTitle = self.book.title ? self.book.title : @"";
            NSString *bookSubtitle = [self subtitleDisplayStringHTML:NO];
            
            [bookAttribs addObject:[BookDetailTableViewCell 
                                    displayStringWithTitle:bookTitle
                                    subtitle:nil
                                    separator:nil
                                    fontSize:18.0]];

            [bookAttribs addObject:[BookDetailTableViewCell
                                    displayStringWithTitle:nil
                                    subtitle:bookSubtitle
                                    separator:nil
                                    fontSize:15.0]];
            
            // format
            if (self.book.formats.count) {
                [bookAttribs addObject:[BookDetailTableViewCell 
                                        displayStringWithTitle:@"Format" 
                                        subtitle:[self.book.formats componentsJoinedByString:@","] 
                                        separator:@": "
                                        fontSize:15.0]];
            }

            // summary
            if (self.book.summarys.count) {
                [bookAttribs addObject:[BookDetailTableViewCell 
                                        displayStringWithTitle:@"Summary"
                                        subtitle:[self.book.summarys componentsJoinedByString:@"; "]
                                        separator:@": "
                                        fontSize:15.0]];
            }

            // publisher
            if (self.book.publishers.count) {
                [bookAttribs addObject:[BookDetailTableViewCell 
                                        displayStringWithTitle:@"Publisher"
                                        subtitle:[self.book.publishers componentsJoinedByString:@"; "]
                                        separator:@": "
                                        fontSize:15.0]];
            }

            // edition
            if (self.book.editions.count) {
                [bookAttribs addObject:[BookDetailTableViewCell 
                                        displayStringWithTitle:@"Edition"
                                        subtitle:[self.book.editions componentsJoinedByString:@", "]
                                        separator:@": "
                                        fontSize:15.0]];
            }

            // description
            if (self.book.extents.count) {
                [bookAttribs addObject:[BookDetailTableViewCell 
                                        displayStringWithTitle:@"Description"
                                        subtitle:[self.book.extents componentsJoinedByString:@", "]
                                        separator:@": "
                                        fontSize:15.0]];
            }

            // isbn
            if (self.book.isbns.count) {
                [bookAttribs addObject:[BookDetailTableViewCell 
                                        displayStringWithTitle:@"ISBN"
                                        subtitle:[self.book.isbns componentsJoinedByString:@" : "]
                                        separator:@": "
                                        fontSize:15.0]];
            }
            
            self.bookInfo = [NSArray arrayWithArray:bookAttribs];

            self.loadingStatus = BookLoadingStatusCompleted;
            [self.tableView reloadData];
        }
    };
    
    LibrariesModule *librariesModule = (LibrariesModule *)[MIT_MobileAppDelegate moduleForTag:LibrariesTag];
    librariesModule.requestQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    [librariesModule.requestQueue addOperation:request];
}
    
- (CGFloat)titleHeight:(UITableView *)tableView {
    CGSize titleSize = [self.book.title sizeWithFont:
        [UIFont fontWithName:STANDARD_FONT size:CELL_STANDARD_FONT_SIZE] 
                                   constrainedToSize:CGSizeMake(tableView.frame.size.width-2*HORIZONTAL_MARGIN, 400)];
    return titleSize.height;
}

- (CGFloat)authorYearHeight:(UITableView *)tableView {
    CGSize authorYearSize = [[self.book authorYear] sizeWithFont:
                             [UIFont fontWithName:STANDARD_FONT size:CELL_DETAIL_FONT_SIZE] 
                                               constrainedToSize:CGSizeMake(tableView.frame.size.width-2*HORIZONTAL_MARGIN, 400)];
    return authorYearSize.height;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger sections = 2; // one for book info, one for email & cite
    if (self.loadingStatus == BookLoadingStatusCompleted) {
        NSInteger numHoldings = self.book.holdings.count;
        if ([self.book.holdings objectForKey:MITLibrariesOCLCCode]) {
            sections++; // one section for MIT holdings
            numHoldings--;
        }
        if (numHoldings > 0) {
            sections++; // one section for all other holdings
        }
    }
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView 
 numberOfRowsInSection:(NSInteger)section {
    if (self.loadingStatus == BookLoadingStatusCompleted) {
        NSInteger rows = 0;
        switch (section) {
            case kInfoSection:
                rows = self.bookInfo.count;
                break;
            case kEmailAndCiteSection:
                rows = 1;
                break;
            case kMITHoldingSection: {
                WorldCatHolding *mitHoldings = [self.book.holdings objectForKey:MITLibrariesOCLCCode];
                rows = [[mitHoldings libraryAvailability] count] + 1;
                break;
            }
            default: // one of the holdings sections
                rows = 1;
                break;
        }
        return rows;
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *infoIdentifier = @"info";
    static NSString *availabilityIdentifier = @"availability";
    static NSString *defaultIdentifier = @"default";
    
    UITableViewCell *cell = nil; 
    
    switch (indexPath.section) {
        case kInfoSection: {
            cell = [tableView dequeueReusableCellWithIdentifier:infoIdentifier];
            if (!cell) {
                cell = [[[BookDetailTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                       reuseIdentifier:infoIdentifier] autorelease];
            }
            NSAttributedString *displayString = [self.bookInfo objectAtIndex:indexPath.row];
            ((BookDetailTableViewCell *)cell).displayString = displayString;
            break;
        }
        case kMITHoldingSection: {
            if (indexPath.row == 0) {
                cell = [tableView dequeueReusableCellWithIdentifier:defaultIdentifier];
                if (!cell) {
                    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:defaultIdentifier] autorelease];
                }
            } else {
                cell = [tableView dequeueReusableCellWithIdentifier:availabilityIdentifier];
                if (!cell) {
                    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:availabilityIdentifier] autorelease];
                }
            }
            [self configureCell:cell forRowAtIndexPath:indexPath];
            break;
        }
        default: {
            cell = [tableView dequeueReusableCellWithIdentifier:defaultIdentifier];
            if (!cell) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault 
                                               reuseIdentifier:defaultIdentifier] autorelease];
            }
            [self configureCell:cell forRowAtIndexPath:indexPath];
            break;
        }
    }
    
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell 
    forRowAtIndexPath:(NSIndexPath *)indexPath 
{
    switch (indexPath.section) {
        case kEmailAndCiteSection:
            cell.accessoryView = [UIImageView accessoryViewWithMITType:MITAccessoryViewEmail];
            cell.textLabel.text = @"Email & Cite Item";
            break;
        case kMITHoldingSection: {
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            switch (indexPath.row) {
                case 0:
                    cell.accessoryView = [UIImageView accessoryViewWithMITType:MITAccessoryViewExternal];
                    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
                    cell.textLabel.text = @"Request Item";
                    break;
                default: {
                    WorldCatHolding *mitHoldings = [self.book.holdings objectForKey:MITLibrariesOCLCCode];
                    
                    NSArray *libraries = [[mitHoldings libraryAvailability] allKeys];
                    libraries = [libraries sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
                    
                    NSString *location = [libraries objectAtIndex:indexPath.row - 1];
                    NSUInteger available = [mitHoldings inLibraryCountForLocation:location];
                    NSUInteger total = [[[mitHoldings libraryAvailability] objectForKey:location] count];

                    cell.textLabel.text = location;
                    cell.textLabel.numberOfLines = 0;
                    cell.textLabel.lineBreakMode = UILineBreakModeWordWrap;
                    
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld of %ld available", available, total];
                    cell.detailTextLabel.numberOfLines = 1;
                    cell.detailTextLabel.lineBreakMode = UILineBreakModeTailTruncation;
                    
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
                    break;
                }
            }
            break;
        }
        case kBLCHoldingSection:
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.text = @"View Holdings";
            break;
        default:
            break;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat height = tableView.rowHeight;
    switch (indexPath.section) {
        case kInfoSection: {
            NSAttributedString *displayString = [self.bookInfo objectAtIndex:indexPath.row];
            height = [BookDetailTableViewCell sizeForDisplayString:displayString tableView:tableView].height + 8;
            break;
        }
        case kMITHoldingSection: {
            if (indexPath.row >= 1) {
                WorldCatHolding *mitHoldings = [self.book.holdings objectForKey:MITLibrariesOCLCCode];
                NSArray *libraries = [[mitHoldings libraryAvailability] allKeys];
                libraries = [libraries sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
                
                NSString *location = [libraries objectAtIndex:indexPath.row - 1];
                NSUInteger available = [mitHoldings inLibraryCountForLocation:location];
                NSUInteger total = [[[mitHoldings libraryAvailability] objectForKey:location] count];
                
                NSString *detail = [NSString stringWithFormat:@"%ld of %ld available", available, total];
                
                CGSize titleSize = [location sizeWithFont:[UIFont fontWithName:BOLD_FONT size:CELL_STANDARD_FONT_SIZE]
                                     constrainedToSize:CGSizeMake(tableView.frame.size.width, 2000.0) 
                                         lineBreakMode:UILineBreakModeWordWrap];
                
                CGSize detailSize = [detail sizeWithFont:[UIFont fontWithName:STANDARD_FONT size:CELL_DETAIL_FONT_SIZE]
                                       constrainedToSize:CGSizeMake(tableView.frame.size.width, 2000.0) 
                                           lineBreakMode:UILineBreakModeWordWrap];
                
                height = titleSize.height + detailSize.height + 2.0 * 10.0;
            }
            break;
        }
        default:
            break;
    }
    return height;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case kEmailAndCiteSection:
            if ([MFMailComposeViewController canSendMail]) {
                NSString *bodyString = [NSString stringWithFormat:
                                        @"<strong>%@</strong><br/>%@",
                                        self.book.title,
                                        [self subtitleDisplayStringHTML:YES]];
                
                MFMailComposeViewController *mailView = [[[MFMailComposeViewController alloc] init] autorelease];
                [mailView setMailComposeDelegate:self];
                [mailView setSubject:self.book.title];
                [mailView setMessageBody:bodyString isHTML:YES];
                [self presentModalViewController:mailView animated:YES]; 
            }
            break;
        case kMITHoldingSection:
        {
            WorldCatHolding *holding = [self.book.holdings objectForKey:MITLibrariesOCLCCode];
            
            if (indexPath.row == 0) {
                NSURL *url = [NSURL URLWithString:holding.url];
                if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                    [[UIApplication sharedApplication] openURL:url];
                }
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
            } else {
                NSArray *locations = [[holding libraryAvailability] allKeys];
                locations = [locations sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
                
                NSString *location = [locations objectAtIndex:indexPath.row - 1];
                NSArray *holdings = [[holding libraryAvailability] objectForKey:location];
                LibrariesHoldingsDetailViewController *detailVC = [[[LibrariesHoldingsDetailViewController alloc] initWithHoldings:holdings] autorelease];
                detailVC.title = location;
                [self.navigationController pushViewController:detailVC
                                                     animated:YES];
                [tableView deselectRowAtIndexPath:indexPath
                                         animated:YES];
            }
            break;
        }
        case kBLCHoldingSection:
        {
            WorldCatHoldingsViewController *vc = [[[WorldCatHoldingsViewController alloc] initWithStyle:UITableViewStyleGrouped] autorelease];
            vc.book = self.book;
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        default:
            break;
    }
}

- (UIView *) tableView: (UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = nil;
    switch (section) {
        case kMITHoldingSection:
            if (self.loadingStatus == BookLoadingStatusCompleted) {
                title = @"MIT Libraries";
            }
            break;
        case kBLCHoldingSection:
            if (self.loadingStatus == BookLoadingStatusCompleted) {
                title = @"Boston Library Consortium";
            }
            break;
        case kEmailAndCiteSection:
        case kInfoSection:
        default:
            break;
    }
	return [UITableView groupedSectionHeaderWithTitle:title];
}

- (CGFloat)tableView: (UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    switch (section) {
        case kMITHoldingSection:
        case kBLCHoldingSection:
            return GROUPED_SECTION_HEADER_HEIGHT;
        case kEmailAndCiteSection:
        case kInfoSection:
        default:
            return 0;
    }
}

- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError*)error 
{
	[self dismissModalViewControllerAnimated:YES];
}

@end
