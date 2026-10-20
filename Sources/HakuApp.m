#import <UIKit/UIKit.h>
#import "HakuEngine.h"
#import "HakuArchive.h"

static NSString *exportsRoot(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Haku"]; }
static dispatch_queue_t engineQueue(void) { static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("com.jacklee.haku.engine",DISPATCH_QUEUE_SERIAL);});return queue; }
static void shareFiles(UIViewController *controller,NSArray *files) {
    NSMutableArray *urls=[NSMutableArray array];for(NSString *path in files)if([NSFileManager.defaultManager fileExistsAtPath:path])[urls addObject:[NSURL fileURLWithPath:path]];
    if(!urls.count)return;
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    sheet.popoverPresentationController.sourceView=controller.view;
    sheet.popoverPresentationController.sourceRect=CGRectMake(controller.view.bounds.size.width/2,80,1,1);
    [controller presentViewController:sheet animated:YES completion:nil];
}

@interface HakuCaptureController : UIViewController
@property(nonatomic,strong) NSDictionary *app;
@property(nonatomic,strong) HakuEngine *engine;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UITextView *log;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSString *directory;
@property(nonatomic,strong) NSMutableString *messages;
@end
@implementation HakuCaptureController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.app[@"name"];self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.modalInPresentation=YES;self.messages=[NSMutableString string];self.engine=[HakuEngine new];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.status=[UILabel new];self.status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];self.status.numberOfLines=0;self.status.text=@"Preparing export…";
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[self.spinner startAnimating];
    self.log=[UITextView new];self.log.editable=NO;self.log.backgroundColor=UIColor.secondarySystemBackgroundColor;self.log.layer.cornerRadius=12;self.log.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];self.log.textContainerInset=UIEdgeInsetsMake(12,12,12,12);self.log.accessibilityIdentifier=@"captureLog";
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[self.spinner,self.status]];header.spacing=16;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.log]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],[stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],[self.spinner.widthAnchor constraintEqualToConstant:24]]];
    __weak typeof(self) weakSelf=self;
    self.engine.progress=^(NSString *message) { dispatch_async(dispatch_get_main_queue(),^{typeof(self) self=weakSelf;if(!self)return;self.status.text=message;[self.messages appendFormat:@"%@\n",message];self.log.text=self.messages;[self.log scrollRangeToVisible:NSMakeRange(self.log.text.length,0)];}); };
    NSString *name=[NSString stringWithFormat:@"%@-%@",self.app[@"bundle"],NSUUID.UUID.UUIDString];self.directory=[exportsRoot() stringByAppendingPathComponent:name];
    HakuEngine *engine=self.engine;NSString *bundle=self.app[@"bundle"],*directory=self.directory;
    BOOL previousIdleTimerDisabled=UIApplication.sharedApplication.isIdleTimerDisabled;
    UIApplication.sharedApplication.idleTimerDisabled=YES;
    dispatch_async(engineQueue(),^{
        NSError *error=nil;NSDictionary *result=[engine captureBundle:bundle output:directory keepAlive:YES error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            UIApplication.sharedApplication.idleTimerDisabled=previousIdleTimerDisabled;
            typeof(self) self=weakSelf;if(!self)return;[self.spinner stopAnimating];self.modalInPresentation=NO;
            self.status.text=result?([result[@"fully_verified"] boolValue]?@"Export verified":@"Main verified · partial export"):error.localizedDescription;
            self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
            self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:result?@"Share":@"Report" style:UIBarButtonItemStylePlain target:self action:@selector(share)];
        });
    });
}
- (void)cancel { self.navigationItem.leftBarButtonItem.enabled=NO;self.status.text=@"Cancelling…";[self.engine cancel]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)share { shareFiles(self,@[[self.directory stringByAppendingPathComponent:@"export.ipa"],[self.directory stringByAppendingPathComponent:@"report.json"]]); }
@end

@interface HakuExportsController : UITableViewController
@property(nonatomic,strong) NSArray *directories;
@end
@implementation HakuExportsController
- (void)viewDidLoad { [super viewDidLoad];self.title=@"Exports";self.tableView.rowHeight=76; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];NSString *root=exportsRoot();NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil];
    self.directories=[names sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){ NSDictionary *aa=[NSFileManager.defaultManager attributesOfItemAtPath:[root stringByAppendingPathComponent:a] error:nil],*bb=[NSFileManager.defaultManager attributesOfItemAtPath:[root stringByAppendingPathComponent:b] error:nil];return [bb[NSFileCreationDate] compare:aa[NSFileCreationDate]]; }];[self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.directories.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSString *directory=[exportsRoot() stringByAppendingPathComponent:self.directories[indexPath.row]];
    NSDictionary *report=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"report.json"]] ?: [NSData data] options:0 error:nil];
    cell.textLabel.text=report[@"bundle"] ?: self.directories[indexPath.row];cell.detailTextLabel.text=[NSString stringWithFormat:@"%@  %@ · %@",report[@"version"] ?: @"",report[@"build"] ?: @"",report[@"status"] ?: @"Interrupted"];
    cell.imageView.image=[UIImage systemImageNamed:[report[@"fully_verified"] boolValue]?@"checkmark.seal.fill":@"doc.zipper"];cell.imageView.tintColor=UIColor.systemTealColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSString *directory=[exportsRoot() stringByAppendingPathComponent:self.directories[indexPath.row]];shareFiles(self,@[[directory stringByAppendingPathComponent:@"export.ipa"],[directory stringByAppendingPathComponent:@"report.json"]]);[tableView deselectRowAtIndexPath:indexPath animated:YES]; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(style!=UITableViewCellEditingStyleDelete)return;
    NSString *directory=[exportsRoot() stringByAppendingPathComponent:self.directories[indexPath.row]];
    NSError *error=nil;
    if([NSFileManager.defaultManager removeItemAtPath:directory error:&error]) { NSMutableArray *remaining=self.directories.mutableCopy;[remaining removeObjectAtIndex:indexPath.row];self.directories=remaining;[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic]; }
    else { UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Could not remove export" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil]; }
}
@end

@interface HakuApplicationsController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<NSDictionary *> *apps,*filtered;
@property(nonatomic,strong) UISearchController *search;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,strong) HakuEngine *engine;
@end
@implementation HakuApplicationsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Haku";self.navigationController.navigationBar.prefersLargeTitles=YES;self.tableView.rowHeight=74;self.tableView.accessibilityIdentifier=@"applicationList";
    self.search=[[UISearchController alloc] initWithSearchResultsController:nil];self.search.searchResultsUpdater=self;self.search.obscuresBackgroundDuringPresentation=NO;self.search.searchBar.placeholder=@"Search applications";self.navigationItem.searchController=self.search;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Exports" style:UIBarButtonItemStylePlain target:self action:@selector(exports)];
    self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,116)];self.subtitle=[[UILabel alloc] initWithFrame:CGRectMake(20,8,280,96)];self.subtitle.autoresizingMask=UIViewAutoresizingFlexibleWidth;self.subtitle.numberOfLines=0;self.subtitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];self.subtitle.textColor=UIColor.secondaryLabelColor;self.subtitle.text=@"Choose an app to export. The selected app restarts during capture.\n\nLoading applications…";[header addSubview:self.subtitle];self.tableView.tableHeaderView=header;[self reload];
}
- (void)reload {
    if(self.engine)return;self.engine=[HakuEngine new];HakuEngine *engine=self.engine;__weak typeof(self) weakSelf=self;
    dispatch_async(engineQueue(),^{ NSError *error=nil;NSArray *apps=[engine applications:&error];dispatch_async(dispatch_get_main_queue(),^{ typeof(self) self=weakSelf;if(!self)return;self.engine=nil;[self.refreshControl endRefreshing];self.apps=apps ?: @[];self.subtitle.text=apps?[NSString stringWithFormat:@"Choose an app to export. The selected app restarts during capture.\n\n%lu applications · On-device export",(unsigned long)apps.count]:[NSString stringWithFormat:@"%@\n\nPull down to retry.",error.localizedDescription];[self updateSearchResultsForSearchController:self.search]; }); });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { NSString *query=searchController.searchBar.text ?: @"";self.filtered=query.length?[self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *app,NSDictionary *bindings) { return [app[@"name"] localizedCaseInsensitiveContainsString:query] || [app[@"bundle"] localizedCaseInsensitiveContainsString:query]; }]]:self.apps;[self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *app=self.filtered[indexPath.row];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=app[@"name"];cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",app[@"version"],app[@"bundle"]];cell.imageView.image=[UIImage systemImageNamed:@"app.dashed"];cell.imageView.tintColor=UIColor.systemTealColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.accessibilityIdentifier=app[@"bundle"];return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { HakuCaptureController *controller=[HakuCaptureController new];controller.app=self.filtered[indexPath.row];[self presentViewController:[[UINavigationController alloc] initWithRootViewController:controller] animated:YES completion:nil];[tableView deselectRowAtIndexPath:indexPath animated:YES]; }
- (void)exports { [self.navigationController pushViewController:[[HakuExportsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
@end

@interface HakuAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation HakuAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options { self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.tintColor=UIColor.systemTealColor;self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[[HakuApplicationsController alloc] initWithStyle:UITableViewStyleInsetGrouped]];[self.window makeKeyAndVisible];return YES; }
@end

int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc>1) {
            NSError *error=nil;id result=nil;HakuEngine *engine=[HakuEngine new];engine.progress=^(NSString *message){fprintf(stderr,"%s\n",message.UTF8String);};
            if(argc==2 && !strcmp(argv[1],"--list"))result=[engine applications:&error];
            else if(argc==4 && !strcmp(argv[1],"--dump"))result=[engine captureBundle:@(argv[2]) output:@(argv[3]) keepAlive:YES error:&error];
            else if(argc==4 && !strcmp(argv[1],"--archive-test")) { BOOL ok=HakuCreateArchive(@(argv[2]),@(argv[3]),&error) && HakuVerifyArchive(@(argv[3]),&error);if(ok)result=@{@"zip_verified":@YES}; }
            else if(argc==3 && !strcmp(argv[1],"--verify-archive")) { if(HakuVerifyArchive(@(argv[2]),&error))result=@{@"zip_verified":@YES}; }
            else {fprintf(stderr,"Usage: Haku --list | --dump BUNDLE NEW_ABSOLUTE_FOLDER | --verify-archive ZIP | --archive-test PAYLOAD NEW_ZIP\n");return 2;}
            if(!result) {fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}
            NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);return 0;
        }
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(HakuAppDelegate.class));
    }
}
