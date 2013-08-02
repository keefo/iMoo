
#import "MyWindowController.h"

#import "DownloadViewController.h"

#import "ChildNode.h"
#import "ImageAndTextCell.h"
#import "SeparatorCell.h"

#define COLUMNID_NAME			@"NameColumn"	// the single column name in our outline view
#define INITIAL_INFODICT		@"Outline"		// name of the dictionary file to populate our outline view

#define UNTITLED_NAME			@"Untitled"		// default name for added folders and leafs

#define HTTP_PREFIX				@"http://"

#define DOWNLOAD_URL			@"download://"

// default section titles
#define VIDEO_NAME				@"网站"
#define MOVIE_NAME				@"电影"
#define DOWNLOAD_NAME			@"下载"
#define GAME_NAME				@"游戏"

// keys in our disk-based dictionary representing our outline view's data
#define KEY_NAME				@"name"
#define KEY_URL					@"url"
#define KEY_SEPARATOR			@"separator"
#define KEY_GROUP				@"group"
#define KEY_FOLDER				@"folder"
#define KEY_ENTRIES				@"entries"

#define kMinOutlineViewSplit	170.0f

#define kNodesPBoardType		@"myNodesPBoardType"	// drag and drop pasteboard type


// -------------------------------------------------------------------------------
//	TreeAdditionObj
//
//	This object is used for passing data between the main and secondary thread
//	which populates the outline view.
// -------------------------------------------------------------------------------
@interface TreeAdditionObj : NSObject
{
	NSIndexPath *indexPath;
	NSString	*nodeURL;
	NSString	*nodeName;
	NSImage		*nodeIcon;
	BOOL		selectItsParent;
}

@property (readonly) NSIndexPath *indexPath;
@property (readonly) NSString *nodeURL;
@property (readonly) NSString *nodeName;
@property (readonly) NSImage  *nodeIcon;
@property (readonly) BOOL selectItsParent;
@end

@implementation TreeAdditionObj
@synthesize indexPath, nodeURL, nodeName, nodeIcon, selectItsParent;

// -------------------------------------------------------------------------------
- (id)initWithURL:(NSString *)url withName:(NSString *)name  selectItsParent:(BOOL)select
{
	self = [super init];
	
	nodeName = name;
	nodeURL = url;
	nodeIcon = nil;
	selectItsParent = select;
	return self;
}

- (id)initWithURL:(NSString *)url withName:(NSString *)name  withIcon:(NSImage *)icon selectItsParent:(BOOL)select
{
	self = [super init];
	
	nodeName = name;
	nodeURL = url;
	nodeIcon = icon;
	selectItsParent = select;
	return self;
}
@end


@implementation MyWindowController

@synthesize dragNodesArray;

// -------------------------------------------------------------------------------
//	initWithWindow:window:
// -------------------------------------------------------------------------------
-(id)initWithWindow:(NSWindow *)window
{
	self = [super initWithWindow:window];
	if (self)
	{
		contents = [[NSMutableArray alloc] init];
		
		// cache the reused icon images
		folderImage = [[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)] retain];
		[folderImage setSize:NSMakeSize(16,16)];
		
		urlImage = [[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericURLIcon)] retain];
		[urlImage setSize:NSMakeSize(16,16)];
	}
	
	return self;
}

// -------------------------------------------------------------------------------
//	dealloc:
// -------------------------------------------------------------------------------
- (void)dealloc
{
	[folderImage release];
	[urlImage release];
		
	[contents release];
	
	[separatorCell release];
	
	self.dragNodesArray = nil;
	
	[super dealloc];
}

// -------------------------------------------------------------------------------
//	awakeFromNib:
// -------------------------------------------------------------------------------
- (void)awakeFromNib
{
	// load view controllers for later use
	downloadViewController = [[DownloadViewController alloc] initWithNibName:@"DownloadView" bundle:nil];
	
	
	[[self window] setAutorecalculatesContentBorderThickness:YES forEdge:NSMinYEdge];
	[[self window] setContentBorderThickness:24 forEdge:NSMinYEdge];
	
	// apply our custom ImageAndTextCell for rendering the first column's cells
	NSTableColumn *tableColumn = [self.myOutlineView tableColumnWithIdentifier:COLUMNID_NAME];
	ImageAndTextCell *imageAndTextCell = [[[ImageAndTextCell alloc] init] autorelease];
	[imageAndTextCell setEditable:YES];
	[tableColumn setDataCell:imageAndTextCell];
   
	separatorCell = [[SeparatorCell alloc] init];
    [separatorCell setEditable:NO];
	
	// build our default tree on a separate thread,
	// some portions are from disk which could get expensive depending on the size of the dictionary file:
	[NSThread detachNewThreadSelector:	@selector(populateOutlineContents:)
										toTarget:self		// we are the target
										withObject:nil];
	
	// add images to our add/remove buttons
	NSImage *addImage = [NSImage imageNamed:NSImageNameAddTemplate];
	[addFolderButton setImage:addImage];
	NSImage *removeImage = [NSImage imageNamed:NSImageNameRemoveTemplate];
	[removeButton setImage:removeImage];
	
	// insert an empty menu item at the beginning of the drown down button's menu and add its image
	NSImage *actionImage = [NSImage imageNamed:NSImageNameActionTemplate];
	[actionImage setSize:NSMakeSize(10,10)];
	
	NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
	[[actionButton menu] insertItem:menuItem atIndex:0];
	[menuItem setImage:actionImage];
	[menuItem release];
	
	// scroll to the top in case the outline contents is very long
	[[[self.myOutlineView enclosingScrollView] verticalScroller] setFloatValue:0.0];
	[[[self.myOutlineView enclosingScrollView] contentView] scrollToPoint:NSMakePoint(0,0)];
	
	// make our outline view appear with gradient selection, and behave like the Finder, iTunes, etc.
	[self.myOutlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
	
	// drag and drop support
	[self.myOutlineView registerForDraggedTypes:[NSArray arrayWithObjects:
											kNodesPBoardType,			// our internal drag type
											NSURLPboardType,			// single url from pasteboard
											NSFilenamesPboardType,		// from Safari or Finder
											NSFilesPromisePboardType,	// from Safari or Finder (multiple URLs)
											nil]];
											
	[webView setUIDelegate:self];	// be the webView's delegate to capture NSResponder calls

}

// -------------------------------------------------------------------------------
//	setContents:newContents
// -------------------------------------------------------------------------------
- (void)setContents:(NSArray*)newContents
{
	if (contents != newContents)
	{
		[contents release];
		contents = [[NSMutableArray alloc] initWithArray:newContents];
	}
}

// -------------------------------------------------------------------------------
//	contents:
// -------------------------------------------------------------------------------
- (NSMutableArray *)contents
{
	return contents;
}

// -------------------------------------------------------------------------------
//	selectParentFromSelection:
//
//	Take the currently selected node and select its parent.
// -------------------------------------------------------------------------------
- (void)selectParentFromSelection
{
	if ([[treeController selectedNodes] count] > 0)
	{
		NSTreeNode* firstSelectedNode = [[treeController selectedNodes] objectAtIndex:0];
		NSTreeNode* parentNode = [firstSelectedNode parentNode];
		if (parentNode)
		{
			// select the parent
			NSIndexPath* parentIndex = [parentNode indexPath];
			[treeController setSelectionIndexPath:parentIndex];
		}
		else
		{
			// no parent exists (we are at the top of tree), so make no selection in our outline
			NSArray* selectionIndexPaths = [treeController selectionIndexPaths];
			[treeController removeSelectionIndexPaths:selectionIndexPaths];
		}
	}
}

// -------------------------------------------------------------------------------
//	performAddFolder:treeAddition
// -------------------------------------------------------------------------------
-(void)performAddFolder:(TreeAdditionObj *)treeAddition
{
	// NSTreeController inserts objects using NSIndexPath, so we need to calculate this
	NSIndexPath *indexPath = nil;
	
	// if there is no selection, we will add a new group to the end of the contents array
	if ([[treeController selectedObjects] count] == 0)
	{
		// there's no selection so add the folder to the top-level and at the end
		indexPath = [NSIndexPath indexPathWithIndex:[contents count]];
	}
	else
	{
		// get the index of the currently selected node, then add the number its children to the path -
		// this will give us an index which will allow us to add a node to the end of the currently selected node's children array.
		//
		indexPath = [treeController selectionIndexPath];
		if ([[[treeController selectedObjects] objectAtIndex:0] isLeaf])
		{
			// user is trying to add a folder on a selected child,
			// so deselect child and select its parent for addition
			[self selectParentFromSelection];
		}
		else
		{
			indexPath = [indexPath indexPathByAddingIndex:[[[[treeController selectedObjects] objectAtIndex:0] children] count]];
		}
	}
	
	ChildNode *node = [[ChildNode alloc] init];
	[node setNodeTitle:[treeAddition nodeName]];
	
	// the user is adding a child node, tell the controller directly
	[treeController insertObject:node atArrangedObjectIndexPath:indexPath];
	
	[node release];
}

// -------------------------------------------------------------------------------
//	addFolder:folderName:
// -------------------------------------------------------------------------------
- (void)addFolder:(NSString *)folderName
{
	TreeAdditionObj *treeObjInfo = [[TreeAdditionObj alloc] initWithURL:nil withName:folderName selectItsParent:NO];
	
	if (buildingOutlineView)
	{
		// add the folder to the tree controller, but on the main thread to avoid lock ups
		[self performSelectorOnMainThread:@selector(performAddFolder:) withObject:treeObjInfo waitUntilDone:YES];
	}
	else
	{
		[self performAddFolder:treeObjInfo];
	}
	
	[treeObjInfo release];
}

// -------------------------------------------------------------------------------
//	addFolderAction:sender:
// -------------------------------------------------------------------------------
- (IBAction)addFolderAction:(id)sender
{
	[self addFolder:UNTITLED_NAME];
}

// -------------------------------------------------------------------------------
//	performAddChild:treeAddition
// -------------------------------------------------------------------------------
-(void)performAddChild:(TreeAdditionObj *)treeAddition
{
	if ([[treeController selectedObjects] count] > 0)
	{
		// we have a selection
		if ([[[treeController selectedObjects] objectAtIndex:0] isLeaf])
		{
			// trying to add a child to a selected leaf node, so select its parent for add
			[self selectParentFromSelection];
		}
	}
	
	// find the selection to insert our node
	NSIndexPath *indexPath;
	if ([[treeController selectedObjects] count] > 0)
	{
		// we have a selection, insert at the end of the selection
		indexPath = [treeController selectionIndexPath];
		indexPath = [indexPath indexPathByAddingIndex:[[[[treeController selectedObjects] objectAtIndex:0] children] count]];
	}
	else
	{
		// no selection, just add the child to the end of the tree
		indexPath = [NSIndexPath indexPathWithIndex:[contents count]];
	}
	
	// create a leaf node
	ChildNode *node = [[ChildNode alloc] initLeaf];
	[node setURL:[treeAddition nodeURL]];
	if ([treeAddition nodeIcon]) {
		[node setNodeIcon:[treeAddition nodeIcon]];
	}
	if ([treeAddition nodeURL])
	{
		if ([[treeAddition nodeURL] length] > 0)
		{
			// the child to insert has a valid URL, use its display name as the node title
			if ([treeAddition nodeName])
				[node setNodeTitle:[treeAddition nodeName]];
			else
				[node setNodeTitle:[[NSFileManager defaultManager] displayNameAtPath:[node urlString]]];
		}
		else
		{
			// the child to insert will be an empty URL
			[node setNodeTitle:UNTITLED_NAME];
			[node setURL:HTTP_PREFIX];
		}
	}
	
	// the user is adding a child node, tell the controller directly
	[treeController insertObject:node atArrangedObjectIndexPath:indexPath];

	[node release];
	
	// adding a child automatically becomes selected by NSOutlineView, so keep its parent selected
	if ([treeAddition selectItsParent])
		[self selectParentFromSelection];
}

#pragma mark - addChild
// -------------------------------------------------------------------------------
//	addChild:url:withName:
// -------------------------------------------------------------------------------
- (void)addChild:(NSString *)url withName:(NSString *)nameStr selectParent:(BOOL)select
{
	TreeAdditionObj *treeObjInfo = [[TreeAdditionObj alloc] initWithURL:url withName:nameStr selectItsParent:select];
	
	if (buildingOutlineView)
	{
		// add the child node to the tree controller, but on the main thread to avoid lock ups
		[self performSelectorOnMainThread:@selector(performAddChild:) withObject:treeObjInfo waitUntilDone:YES];
	}
	else
	{
		[self performAddChild:treeObjInfo];
	}
	
	[treeObjInfo release];
}

- (void)addChild:(NSString *)url withName:(NSString *)nameStr  withIcon:(NSImage *)icon selectParent:(BOOL)select
{
	TreeAdditionObj *treeObjInfo = [[TreeAdditionObj alloc] initWithURL:url withName:nameStr withIcon:icon selectItsParent:select];
	
	if (buildingOutlineView)
	{
		// add the child node to the tree controller, but on the main thread to avoid lock ups
		[self performSelectorOnMainThread:@selector(performAddChild:) withObject:treeObjInfo waitUntilDone:YES];
	}
	else
	{
		[self performAddChild:treeObjInfo];
	}
	
	[treeObjInfo release];
}


// -------------------------------------------------------------------------------
//	addEntries:
// -------------------------------------------------------------------------------
-(void)addEntries:(NSDictionary *)entries
{
	NSEnumerator *entryEnum = [entries objectEnumerator];
	
	id entry;
	while ((entry = [entryEnum nextObject]))
	{
		if ([entry isKindOfClass:[NSDictionary class]])
		{
			NSString *urlStr = [entry objectForKey:KEY_URL];
			
			if ([entry objectForKey:KEY_SEPARATOR])
			{
				// its a separator mark, we treat is as a leaf
				[self addChild:nil withName:nil selectParent:YES];
			}
			else if ([entry objectForKey:KEY_FOLDER])
			{
				// its a file system based folder,
				// we treat is as a leaf and show its contents in the NSCollectionView
				NSString *folderName = [entry objectForKey:KEY_FOLDER];
				[self addChild:urlStr withName:folderName selectParent:YES];
			}
			else if ([entry objectForKey:KEY_URL])
			{
				// its a leaf item with a URL
				NSString *nameStr = [entry objectForKey:KEY_NAME];
				[self addChild:urlStr withName:nameStr selectParent:YES];
			}
			else
			{
				// it's a generic container
				NSString *folderName = [entry objectForKey:KEY_GROUP];
				[self addFolder:folderName];
				
				// add its children
				NSDictionary *entries = [entry objectForKey:KEY_ENTRIES];
				[self addEntries:entries];
				
				[self selectParentFromSelection];
			}
		}
	}
	
	// inserting children automatically expands its parent, we want to close it
	if ([[treeController selectedNodes] count] > 0)
	{
		NSTreeNode *lastSelectedNode = [[treeController selectedNodes] objectAtIndex:0];
		[self.myOutlineView collapseItem:lastSelectedNode];
	}
}

// -------------------------------------------------------------------------------
//	populateOutline:
//
//	Populate the tree controller from disk-based dictionary (Outline.dict)
// -------------------------------------------------------------------------------
- (void)addOutlineFromFile:(NSString*)file
{
	NSDictionary *initData = [NSDictionary dictionaryWithContentsOfFile:file];
	NSDictionary *entries = [initData objectForKey:KEY_ENTRIES];
	[self addEntries:entries];
}

// -------------------------------------------------------------------------------
//	addVideoSection:
// -------------------------------------------------------------------------------
- (void)addVideoSection
{
	[self addFolder:VIDEO_NAME];    
    [self addChild:@"http://www.beyondcow.com/" withName:@"Beyondcow" withIcon:[NSImage imageNamed:@"news"] selectParent:YES];
	[self addChild:@"http://www.beyondcow.com/forums" withName:@"论坛" withIcon:[NSImage imageNamed:@"news"] selectParent:YES];
	[self addChild:@"http://www.weibo.com/beyondcow" withName:@"微博" withIcon:[NSImage imageNamed:@"news"] selectParent:YES];
	[self addChild:@"http://xiaoliaobaike.com/" withName:@"笑料百科" withIcon:[NSImage imageNamed:@"cartoon"] selectParent:YES];
	[self addChild:@"http://mp3.sogou.com/" withName:@"音乐" withIcon:[NSImage imageNamed:@"music"] selectParent:YES];
	[self selectParentFromSelection];
}

- (void)addMovieSection
{
	[self addFolder:MOVIE_NAME];    
    [self addChild:@"http://samples.mplayerhq.hu/" withName:@"测试电影" withIcon:[NSImage imageNamed:@"movie"] selectParent:YES];
	[self selectParentFromSelection];
}

// -------------------------------------------------------------------------------
//	addDownloadSection:
// -------------------------------------------------------------------------------
- (void)addDownloadSection
{
	[self addFolder:DOWNLOAD_NAME];
	[self addChild:DOWNLOAD_URL withName:@"下载列表" selectParent:YES];	
	[self selectParentFromSelection];
}

- (void)addGameSection
{
	[self addFolder:GAME_NAME];
	[self addChild:@"http://macek.github.com/google_pacman/" withName:@"吃豆人" withIcon:[NSImage imageNamed:@"bean"] selectParent:YES];
	[self selectParentFromSelection];
}

#pragma mark - populateOutlineContents
// -------------------------------------------------------------------------------
//	populateOutlineContents:inObject
//
//	This method is being called on a separate thread to avoid blocking the UI
//	a startup time.
// -------------------------------------------------------------------------------
- (void)populateOutlineContents:(id)inObject
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	buildingOutlineView = YES;		// indicate to ourselves we are building the default tree at startup
		
	[self.myOutlineView setHidden:YES];	// hide the outline view - don't show it as we are building the contents
	
	[self addVideoSection];		// add the "Devices" outline section
	[self addMovieSection];
	[self addDownloadSection];		// add the "Places" outline section
	[self addGameSection];		// add the "Places" outline section
	//[self addOutlineFromFile:[[NSBundle mainBundle] pathForResource:INITIAL_INFODICT ofType:@"dict"]];
	// add the disk-based outline content
	
	buildingOutlineView = NO;		// we're done building our default tree
	
	// remove the current selection
	NSArray *selection = [treeController selectionIndexPaths];
	[treeController removeSelectionIndexPaths:selection];
	
	[self.myOutlineView setHidden:NO];	// we are done populating the outline view content, show it again
	
    int w=[self.myOutlineView frame].size.width;
    [self.splitView setPosition:w+1 ofDividerAtIndex:0];
    [self.splitView setPosition:w-1 ofDividerAtIndex:0];
    
	[pool release];
}


#pragma mark - WebView delegate

// -------------------------------------------------------------------------------
//	webView:makeFirstResponder
//
//	We want to keep the outline view in focus as the user clicks various URLs.
//
//	So this workaround applies to an unwanted side affect to some web pages that might have
//	JavaScript code thatt focus their text fields as we target the web view with a particular URL.
//
// -------------------------------------------------------------------------------
- (void)webView:(WebView *)sender makeFirstResponder:(NSResponder *)responder
{
	if (retargetWebView)
	{
		// we are targeting the webview ourselves as a result of the user clicking
		// a url in our outlineview: don't do anything, but reset our target check flag
		//
		retargetWebView = NO;
	}
	else
	{
		// continue the responder chain
		[[self window] makeFirstResponder:sender];
	}
}

// -------------------------------------------------------------------------------
//	isSpecialGroup:
// -------------------------------------------------------------------------------
- (BOOL)isSpecialGroup:(BaseNode *)groupNode
{ 
	return ([groupNode nodeIcon] == nil &&
			[[groupNode nodeTitle] isEqualToString:VIDEO_NAME] || 
			[[groupNode nodeTitle] isEqualToString:MOVIE_NAME] ||
			[[groupNode nodeTitle] isEqualToString:DOWNLOAD_NAME] ||
			[[groupNode nodeTitle] isEqualToString:GAME_NAME]);
}


#pragma mark - NSOutlineView delegate

//-(BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item
//{
//    // replace this with your logic to determine whether the
//    // disclosure triangle should be hidden for a particular item
//    BaseNode* node = [item representedObject];
//    return ([self isSpecialGroup:node]);
//}
//
//- (BOOL)outlineView:(NSOutlineView *)outlineView shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
//{
//    BaseNode* node = [item representedObject];
//    return ([self isSpecialGroup:node]);
//}

// -------------------------------------------------------------------------------
//	shouldSelectItem:item
// -------------------------------------------------------------------------------
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item;
{
	// don't allow special group nodes (Devices and Places) to be selected
	BaseNode* node = [item representedObject];
	return (![self isSpecialGroup:node]);
}

// -------------------------------------------------------------------------------
//	dataCellForTableColumn:tableColumn:row
// -------------------------------------------------------------------------------
- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	NSCell* returnCell = [tableColumn dataCell];
	
	if ([[tableColumn identifier] isEqualToString:COLUMNID_NAME])
	{
		// we are being asked for the cell for the single and only column
		BaseNode* node = [item representedObject];
		if ([node nodeIcon] == nil && [[node nodeTitle] length] == 0)
			returnCell = separatorCell;
	}
	
	return returnCell;
}

// -------------------------------------------------------------------------------
//	textShouldEndEditing:
// -------------------------------------------------------------------------------
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	if ([[fieldEditor string] length] == 0)
	{
		// don't allow empty node names
		return NO;
	}
	else
	{
		return YES;
	}
}

// -------------------------------------------------------------------------------
//	shouldEditTableColumn:tableColumn:item
//
//	Decide to allow the edit of the given outline view "item".
// -------------------------------------------------------------------------------
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BOOL result = YES;
	
	item = [item representedObject];
	if ([self isSpecialGroup:item])
	{
		result = NO; // don't allow special group nodes to be renamed
	}
	else
	{
		if ([[item urlString] isAbsolutePath])
			result = NO;	// don't allow file system objects to be renamed
	}
	
	return result;
}

// -------------------------------------------------------------------------------
//	outlineView:willDisplayCell
// -------------------------------------------------------------------------------
- (void)outlineView:(NSOutlineView *)olv willDisplayCell:(NSCell*)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{	 
	if ([[tableColumn identifier] isEqualToString:COLUMNID_NAME])
	{
		// we are displaying the single and only column
		if ([cell isKindOfClass:[ImageAndTextCell class]])
		{
			item = [item representedObject];
			if (item)
			{
				if ([item isLeaf])
				{
					// does it have a URL string?
					NSString *urlStr = [item urlString];
					if (urlStr)
					{
						if ([item isLeaf])
						{
							NSImage *iconImage;
							if ([item nodeIcon])
								iconImage = [item nodeIcon];
							else if ([[item urlString] hasPrefix:HTTP_PREFIX])
								iconImage = urlImage;
							else
								iconImage = [[NSWorkspace sharedWorkspace] iconForFile:urlStr];
							[item setNodeIcon:iconImage];
						}
						else
						{
							NSImage* iconImage = [[NSWorkspace sharedWorkspace] iconForFile:urlStr];
							[item setNodeIcon:iconImage];
						}
					}
					else
					{
						// it's a separator, don't bother with the icon
					}
				}
				else
				{
					// check if it's a special folder (DEVICES or PLACES), we don't want it to have an icon
					if ([self isSpecialGroup:item])
					{
						[item setNodeIcon:nil];
					}
					else
					{
						// it's a folder, use the folderImage as its icon
						[item setNodeIcon:folderImage];
					}
				}
			}
			
			// set the cell's image
			[(ImageAndTextCell*)cell setImage:[item nodeIcon]];
		}
	}
}

// -------------------------------------------------------------------------------
//	removeSubview:
// -------------------------------------------------------------------------------
- (void)removeSubview
{
	// empty selection
	NSArray *subViews = [placeHolderView subviews];
	if ([subViews count] > 0)
	{
		[[subViews objectAtIndex:0] removeFromSuperview];
	}
	
	[placeHolderView displayIfNeeded];	// we want the removed views to disappear right away
}

// -------------------------------------------------------------------------------
//	changeItemView:
// ------------------------------------------------------------------------------
- (void)changeItemView
{
	NSArray		*selection = [treeController selectedNodes];	
	BaseNode	*node = [[selection objectAtIndex:0] representedObject];
	NSString	*urlStr = [node urlString];
	
	if (urlStr)
	{
		if ([urlStr hasPrefix:HTTP_PREFIX])
		{
			// the url is a web-based url
			if (currentView != webView)
			{
				// change to web view
				[self removeSubview];
				currentView = nil;
				[placeHolderView addSubview:webView];
				currentView = webView;
			}
			
			// this will tell our WebUIDelegate not to retarget first responder since some web pages force
			// forus to their text fields - we want to keep our outline view in focus.
			retargetWebView = YES;	
			
			[webView setMainFrameURL:nil];		// reset the webview to an empty frame
			[webView setMainFrameURL:urlStr];	// re-target to the new url
		}
		else if ([urlStr isEqualToString:DOWNLOAD_URL])
		{
			if (currentView != [downloadViewController view] || currentView != [downloadViewController view])
			{
				[placeHolderView displayIfNeeded];	// we want the removed views to disappear right away
				if (!(currentView == [downloadViewController view]))
				{
					// remove the old subview
					[self removeSubview];
					currentView = nil;
				}
				
				// change to icon view to display folder contents
				[placeHolderView addSubview:[downloadViewController view]];
				currentView = [downloadViewController view];
				
				// its a directory - show its contents using NSCollectionView
			}
		}
		else
		{
			// the url is file-system based (folder or file)
		}
		
		NSRect newBounds;
		newBounds.origin.x = 0;
		newBounds.origin.y = 0;
		newBounds.size.width = [[currentView superview] frame].size.width;
		newBounds.size.height = [[currentView superview] frame].size.height;
		[currentView setFrame:[[currentView superview] frame]];
		
		// make sure our added subview is placed and resizes correctly
		[currentView setFrameOrigin:NSMakePoint(0,0)];
		[currentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	}
	else
	{
		// there's no url associated with this node
		// so a container was selected - no view to display
		[self removeSubview];
		currentView = nil;
	}
}

// -------------------------------------------------------------------------------
//	outlineViewSelectionDidChange:notification
// -------------------------------------------------------------------------------
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	if (buildingOutlineView)	// we are currently building the outline view, don't change any view selections
		return;

	// ask the tree controller for the current selection
	NSArray *selection = [treeController selectedObjects];
	if ([selection count] > 1)
	{
		// multiple selection - clear the right side view
		[self removeSubview];
		currentView = nil;
	}
	else
	{
		if ([selection count] == 1)
		{
			// single selection
			[self changeItemView];
		}
		else
		{
			// there is no current selection - no view to display
			[self removeSubview];
			currentView = nil;
		}
	}
}

// ----------------------------------------------------------------------------------------
// outlineView:isGroupItem:item
// ----------------------------------------------------------------------------------------
-(BOOL)outlineView:(NSOutlineView*)outlineView isGroupItem:(id)item
{
	if ([self isSpecialGroup:[item representedObject]])
	{
		return YES;
	}
	else
	{
		return NO;
	}
}


#pragma mark - NSOutlineView drag and drop

// ----------------------------------------------------------------------------------------
// draggingSourceOperationMaskForLocal <NSDraggingSource override>
// ----------------------------------------------------------------------------------------
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	return NSDragOperationMove;
}

// ----------------------------------------------------------------------------------------
// outlineView:writeItems:toPasteboard
// ----------------------------------------------------------------------------------------
- (BOOL)outlineView:(NSOutlineView *)ov writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
	[pboard declareTypes:[NSArray arrayWithObjects:kNodesPBoardType, nil] owner:self];
	
	// keep track of this nodes for drag feedback in "validateDrop"
	self.dragNodesArray = items;
	
	return YES;
}

// -------------------------------------------------------------------------------
//	outlineView:validateDrop:proposedItem:proposedChildrenIndex:
//
//	This method is used by NSOutlineView to determine a valid drop target.
// -------------------------------------------------------------------------------
- (NSDragOperation)outlineView:(NSOutlineView *)ov
						validateDrop:(id <NSDraggingInfo>)info
						proposedItem:(id)item
						proposedChildIndex:(NSInteger)index
{
	NSDragOperation result = NSDragOperationNone;
	
	if (!item)
	{
		// no item to drop on
		result = NSDragOperationGeneric;
	}
	else
	{
		if ([self isSpecialGroup:[item representedObject]])
		{
			// don't allow dragging into special grouped sections (i.e. Devices and Places)
			result = NSDragOperationNone;
		}
		else
		{	
			if (index == -1)
			{
				// don't allow dropping on a child
				result = NSDragOperationNone;
			}
			else
			{
				// drop location is a container
				result = NSDragOperationMove;
			}
		}
	}
	
	return result;
}

// -------------------------------------------------------------------------------
//	handleWebURLDrops:pboard:withIndexPath:
//
//	The user is dragging URLs from Safari.
// -------------------------------------------------------------------------------
- (void)handleWebURLDrops:(NSPasteboard *)pboard withIndexPath:(NSIndexPath *)indexPath
{
	NSArray *pbArray = [pboard propertyListForType:@"WebURLsWithTitlesPboardType"];
	NSArray *urlArray = [pbArray objectAtIndex:0];
	NSArray *nameArray = [pbArray objectAtIndex:1];
	
	NSInteger i;
	for (i = ([urlArray count] - 1); i >=0; i--)
	{
		ChildNode *node = [[ChildNode alloc] init];
		
		[node setLeaf:YES];
		[node setNodeTitle:[nameArray objectAtIndex:i]];
		[node setURL:[urlArray objectAtIndex:i]];
		[treeController insertObject:node atArrangedObjectIndexPath:indexPath];
		
		[node release];
	}
}

// -------------------------------------------------------------------------------
//	handleInternalDrops:pboard:withIndexPath:
//
//	The user is doing an intra-app drag within the outline view.
// -------------------------------------------------------------------------------
- (void)handleInternalDrops:(NSPasteboard*)pboard withIndexPath:(NSIndexPath*)indexPath
{
	// user is doing an intra app drag within the outline view:
	//
	NSArray* newNodes = self.dragNodesArray;

	// move the items to their new place (we do this backwards, otherwise they will end up in reverse order)
	NSInteger i;
	for (i = ([newNodes count] - 1); i >=0; i--)
	{
		[treeController moveNode:[newNodes objectAtIndex:i] toIndexPath:indexPath];
	}
	
	// keep the moved nodes selected
	NSMutableArray* indexPathList = [NSMutableArray array];
	for (i = 0; i < [newNodes count]; i++)
	{
		[indexPathList addObject:[[newNodes objectAtIndex:i] indexPath]];
	}
	[treeController setSelectionIndexPaths: indexPathList];
}

// -------------------------------------------------------------------------------
//	handleFileBasedDrops:pboard:withIndexPath:
//
//	The user is dragging file-system based objects (probably from Finder)
// -------------------------------------------------------------------------------
- (void)handleFileBasedDrops:(NSPasteboard*)pboard withIndexPath:(NSIndexPath*)indexPath
{
	NSArray *fileNames = [pboard propertyListForType:NSFilenamesPboardType];
	if ([fileNames count] > 0)
	{
		NSInteger i;
		NSInteger count = [fileNames count];
		
		for (i = (count - 1); i >=0; i--)
		{
			NSURL* url = [NSURL fileURLWithPath:[fileNames objectAtIndex:i]];
			
			ChildNode *node = [[ChildNode alloc] init];

			NSString* name = [[NSFileManager defaultManager] displayNameAtPath:[url path]];
			[node setLeaf:YES];
			[node setNodeTitle:name];
			[node setURL:[url path]];
			[treeController insertObject:node atArrangedObjectIndexPath:indexPath];
			
			[node release];
		}
	}
}

// -------------------------------------------------------------------------------
//	handleURLBasedDrops:pboard:withIndexPath:
//
//	Handle dropping a raw URL.
// -------------------------------------------------------------------------------
- (void)handleURLBasedDrops:(NSPasteboard*)pboard withIndexPath:(NSIndexPath*)indexPath
{
	NSURL *url = [NSURL URLFromPasteboard:pboard];
	if (url)
	{
		ChildNode *node = [[ChildNode alloc] init];

		if ([url isFileURL])
		{
			// url is file-based, use it's display name
			NSString *name = [[NSFileManager defaultManager] displayNameAtPath:[url path]];
			[node setNodeTitle:name];
			[node setURL:[url path]];
		}
		else
		{
			// url is non-file based (probably from Safari)
			//
			// the url might not end with a valid component name, use the best possible title from the URL
			if ([[[url path] pathComponents] count] == 1)
			{
				if ([[url absoluteString] hasPrefix:HTTP_PREFIX])
				{
					// use the url portion without the prefix
					NSRange prefixRange = [[url absoluteString] rangeOfString:HTTP_PREFIX];
					NSRange newRange = NSMakeRange(prefixRange.length, [[url absoluteString] length]- prefixRange.length - 1);
					[node setNodeTitle:[[url absoluteString] substringWithRange:newRange]];
				}
				else
				{
					// prefix unknown, just use the url as its title
					[node setNodeTitle:[url absoluteString]];
				}
			}
			else
			{
				// use the last portion of the URL as its title
				[node setNodeTitle:[[url path] lastPathComponent]];
			}
				
			[node setURL:[url absoluteString]];
		}
		[node setLeaf:YES];
		
		[treeController insertObject:node atArrangedObjectIndexPath:indexPath];
		
		[node release];
	}
}

// -------------------------------------------------------------------------------
//	outlineView:acceptDrop:item:childIndex
//
//	This method is called when the mouse is released over an outline view that previously decided to allow a drop
//	via the validateDrop method. The data source should incorporate the data from the dragging pasteboard at this time.
//	'index' is the location to insert the data as a child of 'item', and are the values previously set in the validateDrop: method.
//
// -------------------------------------------------------------------------------
- (BOOL)outlineView:(NSOutlineView*)ov acceptDrop:(id <NSDraggingInfo>)info item:(id)targetItem childIndex:(NSInteger)index
{
	// note that "targetItem" is a NSTreeNode proxy
	//
	BOOL result = NO;
	
	// find the index path to insert our dropped object(s)
	NSIndexPath *indexPath;
	if (targetItem)
	{
		// drop down inside the tree node:
		// feth the index path to insert our dropped node
		indexPath = [[targetItem indexPath] indexPathByAddingIndex:index];
	}
	else
	{
		// drop at the top root level
		if (index == -1)	// drop area might be ambibuous (not at a particular location)
			indexPath = [NSIndexPath indexPathWithIndex:[contents count]];		// drop at the end of the top level
		else
			indexPath = [NSIndexPath indexPathWithIndex:index]; // drop at a particular place at the top level
	}

	NSPasteboard *pboard = [info draggingPasteboard];	// get the pasteboard
	
	// check the dragging type -
	if ([pboard availableTypeFromArray:[NSArray arrayWithObject:kNodesPBoardType]])
	{
		// user is doing an intra-app drag within the outline view
		[self handleInternalDrops:pboard withIndexPath:indexPath];
		result = YES;
	}
	else if ([pboard availableTypeFromArray:[NSArray arrayWithObject:@"WebURLsWithTitlesPboardType"]])
	{
		// the user is dragging URLs from Safari
		[self handleWebURLDrops:pboard withIndexPath:indexPath];		
		result = YES;
	}
	else if ([pboard availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]])
	{
		// the user is dragging file-system based objects (probably from Finder)
		[self handleFileBasedDrops:pboard withIndexPath:indexPath];
		result = YES;
	}
	else if ([pboard availableTypeFromArray:[NSArray arrayWithObject:NSURLPboardType]])
	{
		// handle dropping a raw URL
		[self handleURLBasedDrops:pboard withIndexPath:indexPath];
		result = YES;
	}
	
	return result;
}


#pragma mark - Split View Delegate

// -------------------------------------------------------------------------------
//	splitView:constrainMinCoordinate:
//
//	What you really have to do to set the minimum size of both subviews to kMinOutlineViewSplit points.
// -------------------------------------------------------------------------------
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedCoordinate ofSubviewAt:(int)index
{
	return proposedCoordinate + kMinOutlineViewSplit;
}

// -------------------------------------------------------------------------------
//	splitView:constrainMaxCoordinate:
// -------------------------------------------------------------------------------
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedCoordinate ofSubviewAt:(int)index
{
	return proposedCoordinate - kMinOutlineViewSplit;
}

// -------------------------------------------------------------------------------
//	splitView:resizeSubviewsWithOldSize:
//
//	Keep the left split pane from resizing as the user moves the divider line.
// -------------------------------------------------------------------------------
- (void)splitView:(NSSplitView*)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSRect newFrame = [sender frame]; // get the new size of the whole splitView
	NSView *left = [[sender subviews] objectAtIndex:0];
	NSRect leftFrame = [left frame];
	NSView *right = [[sender subviews] objectAtIndex:1];
	NSRect rightFrame = [right frame];
 
	CGFloat dividerThickness = [sender dividerThickness];
	  
	leftFrame.size.height = newFrame.size.height;

	rightFrame.size.width = newFrame.size.width - leftFrame.size.width - dividerThickness;
	rightFrame.size.height = newFrame.size.height;
	rightFrame.origin.x = leftFrame.size.width + dividerThickness;

	[left setFrame:leftFrame];
	[right setFrame:rightFrame];
}

@end
