// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITiledScalingView.h>

#import <OmniUI/OUIScalingScrollView.h>
#import <QuartzCore/QuartzCore.h>

#import <OmniUI/OUITileDebug.h>
#import <OmniUI/OUIScalingViewTile.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@interface _OUITiledScalingViewDrawRequestDebugView : UIView
@end

@implementation _OUITiledScalingViewDrawRequestDebugView
{
    NSTimer *_removeTimer;
}

- (void)dealloc;
{
    [_removeTimer invalidate];
}

- (void)didMoveToSuperview;
{
    [super didMoveToSuperview];
    
    _removeTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_removeTimerFired:) userInfo:nil repeats:NO];
}

- (void)_removeTimerFired:(NSTimer *)timer;
{
    [self removeFromSuperview];
}

@end

@implementation OUITiledScalingView
{
    NSMutableArray *_tiles;
    NSMutableArray *_drawRequestDebugViews;
}

static id _commonInit(OUITiledScalingView *self)
{
    // To support scaling to large sizes, subclasses cannot implement -drawRect:. If it does get drawn, the whole point of tiling (avoiding taking up backing store for our full bounds) will be voided.
    // Our superclass implements it, but we trump that by adding -displayLayer:, doing nothing.
    OBASSERT(OBClassImplementingMethod([self class], @selector(drawRect:)) == [OUIScalingView class]);
        
    // Superclass turns this on, but we don't want it.
    self.layer.needsDisplayOnBoundsChange = NO;
    
    self->_tiles = [[NSMutableArray alloc] init];

    // Checkerboard pattern for areas that don't have tiles generated yet.
    UIImage *patternImage = [UIImage imageNamed:@"OUIScalingViewBackgroundPattern.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT_NOTNULL(patternImage);
    self.layer.backgroundColor = [[UIColor colorWithPatternImage:patternImage] CGColor];
    
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

#pragma mark - UIView subclass

- (void)setNeedsDisplay;
{
    [_tiles makeObjectsPerformSelector:_cmd];
}

- (void)setNeedsDisplayInRect:(CGRect)rect;
{
    for (UIView *tile in _tiles) {
        if (CGRectIntersectsRect(rect, tile.frame)) {
            CGRect tileRect = CGRectIntersection(rect, tile.frame);
            [tile setNeedsDisplayInRect:[tile convertRect:tileRect fromView:self]];
        }
    }
    
    // Show the requested rects briefly
    if (OUIScalingTileViewDebugDrawing > 0) {
        if (!_drawRequestDebugViews)
            _drawRequestDebugViews = [[NSMutableArray alloc] init];
        
        [UIView performWithoutAnimation:^{
            _OUITiledScalingViewDrawRequestDebugView *debugView = [[_OUITiledScalingViewDrawRequestDebugView alloc] initWithFrame:rect];
            debugView.layer.zPosition = 100;
            debugView.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:1.0 alpha:0.1];
            debugView.layer.borderColor = [[UIColor blueColor] CGColor];
            debugView.layer.borderWidth = 1;
            [self addSubview:debugView];
        }];
    }
}

// TODO: -setFrame: -- if our resizing just adds/removes content and the origin is the same, we could only dirty some of the tiles.

#pragma mark -
#pragma mark CALayer delegate

- (void)displayLayer:(CALayer *)layer;
{
    // When tiled, we never, ever, want this view's layer to have content. If it gets content, it will potentially be of massive size (hence, the tiling!)
}


#pragma mark -
#pragma mark API

static void OUITileViewWithRegularSquareTiles(OUITiledScalingView *self, NSMutableArray *tiles)
{
    CGRect bounds = self.bounds;
    if (bounds.size.width == CGFLOAT_MAX) {
        DEBUG_TILE_LAYOUT(1, @"wow, the bounds of this view cannot be correct (%@) - bailing", NSStringFromCGRect(bounds));
        return;
    }
    
    // Yields an even 4x3 tiles on the current iPad screen. If the screen size ever changes, we might want to make this dynamic so that if we are scrolled to a corner we get an even number of tiles.
    static const CGFloat kTileSize = 256;
    
    OUIScalingScrollView *scrollView = (OUIScalingScrollView *)self.superview;
    OBASSERT([scrollView isKindOfClass:[OUIScalingScrollView class]]);
    CGRect visibleRect = CGRectIntersection([scrollView convertRect:scrollView.bounds toView:self], bounds);
    
    DEBUG_TILE_LAYOUT(1, @"Tiling visible %@ with bounds %@", NSStringFromCGRect(visibleRect), NSStringFromCGRect(bounds));
    if (visibleRect.size.width <= 0 || visibleRect.size.height <= 0)
        return;
    
    OBASSERT(CGRectEqualToRect(bounds, CGRectIntegral(bounds)));
    
    NSMutableArray *availableTiles = [[NSMutableArray alloc] initWithArray:tiles];
    
    // Base the number of tiles off our visible area, but their offsets to our bounds origin.
    CGFloat tileStartX = kTileSize * floor((CGRectGetMinX(visibleRect) - CGRectGetMinX(bounds)) / kTileSize);
    CGFloat tileStartY = kTileSize * floor((CGRectGetMinY(visibleRect) - CGRectGetMinY(bounds)) / kTileSize);
    DEBUG_TILE_LAYOUT(1, @"  First tile starts at %f, %f", tileStartX, tileStartY);
    
    NSUInteger tilesWide = (NSUInteger)ceil((CGRectGetMaxX(visibleRect) - tileStartX) / kTileSize);
    NSUInteger tilesHigh = (NSUInteger)ceil((CGRectGetMaxY(visibleRect) - tileStartY) / kTileSize);
    DEBUG_TILE_LAYOUT(1, @"  Using %lu x %lu tiles", tilesWide, (unsigned long)tilesHigh);
    
    
    NSMutableArray *neededRects = nil;
    
    for (NSUInteger tileIndexY = 0; tileIndexY < tilesHigh; tileIndexY++) {
        for (NSUInteger tileIndexX = 0; tileIndexX < tilesWide; tileIndexX++) {
            // No worry about partial pixel accumulation here since we snap to integer pixels above.
            
            // Built the tile rect, clamping to our bounds (partial tiles on the edges).
            CGRect tileFrame = CGRectMake(tileStartX + tileIndexX * kTileSize, tileStartY + tileIndexY * kTileSize, kTileSize, kTileSize);
            tileFrame = CGRectIntersection(tileFrame, bounds);
            
            DEBUG_TILE_LAYOUT(1, @"  Tile frame %@", NSStringFromCGRect(tileFrame));
            
            // Keep existing tiles that match what we need.
            OUIScalingViewTile *existingTile = nil;
            for (OUIScalingViewTile *candidate in availableTiles) {
                if (CGRectEqualToRect(candidate.frame, tileFrame)) {
                    existingTile = candidate;
                    DEBUG_TILE_LAYOUT(1, @"    exists as %@", [existingTile shortDescription]);
                    break;
                }
            }
            
            if (existingTile) {
                existingTile.hidden = NO; // might have been unused before, though this seems likely to be rare
                [availableTiles removeObjectIdenticalTo:existingTile];
            } else {
                if (!neededRects)
                    neededRects = [[NSMutableArray alloc] init];
                [neededRects addObject:[NSValue valueWithCGRect:tileFrame]];
                DEBUG_TILE_LAYOUT(1, @"    queued needed tile rect");
            }
        }
    }
    
    // Now that all the existing tiles that can be reused have been, make new tiles.    
    if (neededRects) {
        DEBUG_TILE_LAYOUT(1, @"  Need new %lu tiles", (unsigned long)[neededRects count]);
        
        // If we are rotating, we don't want to use tiles with existing content. Otherwise, they'll fly across the screen, looking weird.
        // Do allow reuse of hidden tiles here, though, so that multiple rotations don't build up more and more tiles.
        if (self.rotating) {
            NSUInteger tileIndex = [availableTiles count];
            while (tileIndex--) {
                OUIScalingViewTile *tile = [availableTiles objectAtIndex:tileIndex];
                if (tile.hidden == NO)
                    [availableTiles removeObjectAtIndex:tileIndex];
            }
        }
        
        for (NSValue *rectValue in neededRects) {
            CGRect tileFrame = [rectValue CGRectValue];
            OUIScalingViewTile *tile = [availableTiles lastObject];
            if (tile) {
                tile.hidden = NO; // might have been unused before
                [availableTiles removeLastObject]; // Still retained by _tiles.
                DEBUG_TILE_LAYOUT(1, @"    Repurposed tile %@ for rect %@", [tile shortDescription], NSStringFromCGRect(tileFrame));
            } else {
                tile = [[OUIScalingViewTile alloc] init];
                [tiles addObject:tile];
                [self addSubview:tile];
                
                DEBUG_TILE_LAYOUT(1, @"    Created new tile %@ for rect %@", [tile shortDescription], NSStringFromCGRect(tileFrame));
            }
            
            tile.frame = tileFrame;
        }
    }
    
    // Finally, hide any remaining tiles that didn't get reused.
    for (OUIScalingViewTile *tile in availableTiles) {
        DEBUG_TILE_LAYOUT(1, @"  Hiding unused tile %@", [tile shortDescription]);
        tile.hidden = YES;
    }
}

+ (OUITiledScalingViewTiling)tiling;
{
    return OUITileViewWithRegularSquareTiles;
}

// Might want to compute the visible rect from our -layoutSubviews, but for now our containing scroll view calls this.
// The default implementation builds a regular square tiling, reusing tiles that fall on the same frame.
// Subclasses may choose to use non-regular tilings if they have less canvas-y content.
- (void)tileVisibleRect;
{
    [[self class] tiling](self, _tiles);
}

@end
