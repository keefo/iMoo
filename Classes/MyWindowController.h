#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class DownloadViewController;
@class SeparatorCell;

@interface MyWindowController : NSWindowController
{
	IBOutlet NSTreeController	*treeController;
	IBOutlet NSView				*placeHolderView;
	IBOutlet WebView			*webView;
	
	IBOutlet NSButton			*addFolderButton;
	IBOutlet NSButton			*removeButton;
	IBOutlet NSPopUpButton		*actionButton;
	
	NSMutableArray				*contents;
	
	// cached images for generic folder and url document
	NSImage						*folderImage;
	NSImage						*urlImage;
	
	NSView						*currentView;
	DownloadViewController		*downloadViewController;
	
	BOOL						buildingOutlineView;	// signifies we are building the outline view at launch time
	
	NSArray						*dragNodesArray; // used to keep track of dragged nodes
	
	BOOL						retargetWebView;
	
	SeparatorCell				*separatorCell;	// the cell used to draw a separator line in the outline view
}
@property(assign) IBOutlet NSOutlineView *myOutlineView;
@property(assign) IBOutlet NSSplitView *splitView;


@property(retain) NSArray *dragNodesArray;

- (void)setContents:(NSArray *)newContents;
- (NSMutableArray *)contents;

- (IBAction)addFolderAction:(id)sender;
- (IBAction)addBookmarkAction:(id)sender;
- (IBAction)editBookmarkAction:(id)sender;

@end
