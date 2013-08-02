//
//  DownloadViewController.h
//  iMoo
//
//  Created by liam on 11-06-16.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface DownloadViewController : NSViewController {
	IBOutlet NSArrayController	*contentArrayController;
	NSMutableArray				*content;

}
@property(nonatomic, retain) NSMutableArray *content;

@end
