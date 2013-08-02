#import <Cocoa/Cocoa.h>

@interface BaseNode : NSObject <NSCoding, NSCopying>
{
	NSString		*nodeTitle;
	NSMutableArray	*children;
	BOOL			isLeaf;
	NSImage			*nodeIcon;
	NSString		*urlString;
}

- (id)initLeaf;

- (void)setNodeTitle:(NSString *)newNodeTitle;
- (NSString *)nodeTitle;

- (void)setChildren:(NSArray *)newChildren;
- (NSMutableArray *)children;

- (void)setLeaf:(BOOL)flag;
- (BOOL)isLeaf;

- (void)setNodeIcon:(NSImage *)icon;
- (NSImage *)nodeIcon;

- (void)setURL:(NSString *)name;
- (NSString *)urlString;

- (BOOL)isDraggable;

- (NSComparisonResult)compare:(BaseNode *)aNode;

- (NSArray *)mutableKeys;

- (NSDictionary *)dictionaryRepresentation;
- (id)initWithDictionary:(NSDictionary *)dictionary;

- (id)parentFromArray:(NSArray *)array;
- (void)removeObjectFromChildren:(id)obj;
- (NSArray *)descendants;
- (NSArray *)allChildLeafs;
- (NSArray *)groupChildren;
- (BOOL)isDescendantOfOrOneOfNodes:(NSArray *)nodes;
- (BOOL)isDescendantOfNodes:(NSArray *)nodes;
- (NSIndexPath*)indexPathInArray:(NSArray*)array;

@end
