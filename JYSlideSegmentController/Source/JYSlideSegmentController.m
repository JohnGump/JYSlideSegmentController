//
//  JYSlideSegmentController.m
//  JYSlideSegmentController
//
//  Created by Alvin on 14-3-16.
//  Copyright (c) 2014年 Alvin. All rights reserved.
//

#import "JYSlideSegmentController.h"

#define INDICATOR_HEIGHT (3)

#define UIColorFromRGB(rgbValue) \
[UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

NSString * const segmentBarItemID = @"JYSegmentBarItem";

@interface JYSegmentBarItem : UICollectionViewCell

@property (nonatomic, strong) UILabel *titleLabel;

@end


@implementation JYSegmentBarItem

- (id)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    [self.contentView addSubview:self.titleLabel];
  }
  return self;
}

- (UILabel *)titleLabel
{
  if (!_titleLabel) {
    _titleLabel = [[UILabel alloc] initWithFrame:self.contentView.bounds];
    _titleLabel.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    _titleLabel.textAlignment = NSTextAlignmentCenter;
  }
  return _titleLabel;
}

@end

@interface JYSlideView()

//don't trigger scrollViewDidScroll when scrollContentSizeResizing = YES
@property (nonatomic, assign) BOOL scrollContentSizeResizing;

@end

@implementation JYSlideView

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if (gestureRecognizer == self.panGestureRecognizer) {
    if ([self.slideDelegate
            respondsToSelector:
                @selector(slideViewPanGestureRecognizerShouldBegin:)]) {
      return [self.slideDelegate
          slideViewPanGestureRecognizerShouldBegin:gestureRecognizer];
    }
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer *)otherGestureRecognizer
{
  if (gestureRecognizer == self.panGestureRecognizer) {
    if ([self.slideDelegate
            respondsToSelector:
                @selector(slideViewPanGestureRecognizer:
                    shouldRecognizeSimultaneouslyWithGestureRecognizer:)]) {
      return [self.slideDelegate slideViewPanGestureRecognizer:gestureRecognizer
            shouldRecognizeSimultaneouslyWithGestureRecognizer:
                otherGestureRecognizer];
    }
  }
  return YES;
}

@end

@interface JYSlideSegmentController ()
<UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate>

@property (nonatomic, strong, readwrite) UICollectionView *segmentBar;
@property (nonatomic, strong, readwrite) JYSlideView *slideView;
@property (nonatomic, assign, readwrite) NSInteger selectedIndex;
@property (nonatomic, assign, readwrite) NSInteger previousIndex;
@property (nonatomic, assign, readwrite) CGFloat lastDestination;
@property (nonatomic, strong) UIView *indicator;
@property (nonatomic, strong) UIView *indicatorBgView;
@property (nonatomic, strong) UIView *separator;
@property (nonatomic, assign) CGRect currentIndicatorFrame;

@property (nonatomic, strong) UICollectionViewFlowLayout *segmentBarLayout;

@property (nonatomic, assign, getter=isFirstShow) BOOL firstShow;


- (void)reset;

@end

@implementation JYSlideSegmentController
@synthesize viewControllers = _viewControllers;
@synthesize itemWidth = _itemWidth;
@synthesize separatorColor = _separatorColor;

- (instancetype)initWithViewControllers:(NSArray *)viewControllers
{
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _viewControllers = [viewControllers copy];
    _selectedIndex = NSNotFound;
    _startIndex = 0;
    _firstShow = YES;
  }
  return self;
}

- (instancetype)initWithViewControllers:(NSArray *)viewControllers
                             startIndex:(NSInteger)startIndex
{
  NSParameterAssert(startIndex < viewControllers.count);
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _viewControllers = [viewControllers copy];
    _selectedIndex = NSNotFound;
    _previousIndex = NSNotFound;
    _startIndex = startIndex;
    _firstShow = YES;
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [self setupSubviews];
  
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleOrientationDidChangeNotification:)
             name:UIDeviceOrientationDidChangeNotification
           object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  if (self.isFirstShow) {
    [self adjustContentSize];
    [self setSelectedIndex:self.startIndex];
    [self scrollToViewWithIndex:self.startIndex animated:NO];
    [self segmentBarScrollToIndex:self.startIndex animated:NO];
    self.firstShow = NO;
  }
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  
  [self adjustContentSize];
  
  CGRect itemFrame = [self frameForSegmentItemAtIndex:self.selectedIndex];
  CGRect frame = CGRectMake(itemFrame.origin.x,
                            self.segmentBar.frame.size.height - self.indicatorHeight,
                            itemFrame.size.width, self.indicatorHeight);
  self.indicatorBgView.frame = frame;
  CGFloat indicatorWidth = itemFrame.size.width - self.indicatorInsets.left - self.indicatorInsets.right;
  CGRect indicatorFrame = CGRectMake(self.indicatorInsets.left, 0, indicatorWidth, self.indicatorHeight);
  self.indicator.frame = indicatorFrame;
  CGRect separatorFrame = CGRectMake(0, CGRectGetMaxY(self.segmentBar.frame),
                                     CGRectGetWidth(self.segmentBar.frame), self.separatorHeight);
  self.separator.frame = separatorFrame;

  [self configureViewControllerFrame:self.selectedViewController];
  // workaround for 7.x iPad
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad &&
      [[[UIDevice currentDevice] systemVersion] floatValue] < 8.0) {
    [self scrollToViewWithIndex:self.selectedIndex animated:NO];
  }
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Setup
- (void)setupSubviews
{
  // iOS7 set layout
  if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.edgesForExtendedLayout = UIRectEdgeNone;
  }
  [self.view addSubview:self.segmentBar];
  [self.view addSubview:self.slideView];
  [self.segmentBar registerClass:[JYSegmentBarItem class] forCellWithReuseIdentifier:segmentBarItemID];
  [self.segmentBar addSubview:self.indicatorBgView];

  CGRect separatorFrame = CGRectMake(0, CGRectGetMaxY(self.segmentBar.frame),
                                     CGRectGetWidth(self.segmentBar.frame), 1);
  _separator = [[UIView alloc] initWithFrame:separatorFrame];
  [_separator setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin];
  [_separator setBackgroundColor:self.separatorColor];
  [self.view addSubview:_separator];
}

#pragma mark - Property
- (JYSlideView *)slideView
{
  if (!_slideView) {
    _slideView = [[JYSlideView alloc] initWithFrame:CGRectZero];
    CGRect frame = self.view.bounds;
    frame.size.height -= _segmentBar.frame.size.height;
    frame.origin.y = CGRectGetMaxY(_segmentBar.frame);
    _slideView.frame = frame;
    _slideView.scrollEnabled = self.viewControllers.count > 1 ? YES : NO;
    _slideView.scrollContentSizeResizing = NO;
    _slideView.scrollsToTop = NO;
    [_slideView setAutoresizingMask:(UIViewAutoresizingFlexibleWidth
                                     | UIViewAutoresizingFlexibleHeight)];
    [_slideView setShowsHorizontalScrollIndicator:NO];
    [_slideView setShowsVerticalScrollIndicator:NO];
    [_slideView setPagingEnabled:YES];
    [_slideView setBounces:NO];
    [_slideView setDelegate:self];
  }
  return _slideView;
}

- (UICollectionView *)segmentBar
{
  if (!_segmentBar) {
    _segmentBar = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.segmentBarLayout];
    CGRect frame = self.view.bounds;
    frame.size.height = self.segmentBarHeight;
    _segmentBar.frame = frame;
    _segmentBar.backgroundColor = [UIColor whiteColor];
    _segmentBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _segmentBar.delegate = self;
    _segmentBar.dataSource = self;
    _segmentBar.showsHorizontalScrollIndicator = NO;
    _segmentBar.showsVerticalScrollIndicator = NO;
    _segmentBar.scrollsToTop = NO;
  }
  return _segmentBar;
}

- (UIView *)indicatorBgView
{
  if (!_indicatorBgView) {
    _indicatorBgView = [[UIView alloc] initWithFrame:CGRectZero];
    CGRect frame = CGRectMake(0, self.segmentBar.frame.size.height - self.indicatorHeight,
                            self.itemWidth, self.indicatorHeight);
    _indicatorBgView.frame = frame;
    _indicatorBgView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    _indicatorBgView.backgroundColor = [UIColor clearColor];
    [_indicatorBgView addSubview:self.indicator];
  }
  return _indicatorBgView;
}

- (UIView *)indicator
{
  if (!_indicator) {
    _indicator = [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat width = self.itemWidth - self.indicatorInsets.left - self.indicatorInsets.right;
    CGRect frame = CGRectMake(self.indicatorInsets.left, 0, width, self.indicatorHeight);
    _indicator.frame = frame;
    _indicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _indicator.backgroundColor = self.indicatorColor ? : [UIColor yellowColor];
  }
  return _indicator;
}

- (CGFloat)indicatorHeight
{
  if (!_indicatorHeight) {
    _indicatorHeight = INDICATOR_HEIGHT;
  }
  return _indicatorHeight;
}

- (CGFloat)segmentBarHeight
{
  if (!_segmentBarHeight) {
    _segmentBarHeight = 40;
  }
  return _segmentBarHeight;
}

- (CGFloat)separatorHeight
{
    if (!_separatorHeight) {
        _separatorHeight = 1.f;
    }
    return _separatorHeight;
}

- (CGFloat)itemWidth
{
  if (!_itemWidth) {
    _itemWidth = self.view.frame.size.width / self.viewControllers.count;
  }
  return _itemWidth;
}

- (void)setItemWidth:(CGFloat)itemWidth
{
  _itemWidth = itemWidth;
  if (_segmentBarLayout && _segmentBar) {
    _segmentBarLayout.itemSize = CGSizeMake(_itemWidth, self.segmentBarHeight);
    [_segmentBar setCollectionViewLayout:_segmentBarLayout animated:NO];
    [self.view setNeedsLayout];
  }
}

- (void)setSegmentBarColor:(UIColor *)segmentBarColor
{
  _segmentBarColor = segmentBarColor;
  _segmentBar.backgroundColor = _segmentBarColor;
}

- (void)setIndicatorColor:(UIColor *)indicatorColor
{
  _indicatorColor = indicatorColor;
  _indicator.backgroundColor = _indicatorColor;
}

- (UIColor *)separatorColor
{
  if (!_separatorColor) {
    _separatorColor = UIColorFromRGB(0xdcdcdc);
  }
  return _separatorColor;
}

- (void)setSeparatorColor:(UIColor *)separatorColor
{
  _separatorColor = separatorColor;
  self.separator.backgroundColor = _separatorColor;
}


- (UICollectionViewFlowLayout *)segmentBarLayout
{
  if (!_segmentBarLayout) {
    _segmentBarLayout = [[UICollectionViewFlowLayout alloc] init];
    _segmentBarLayout.sectionInset = self.segmentBarInsets;
    _segmentBarLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    _segmentBarLayout.minimumLineSpacing = 0;
    _segmentBarLayout.minimumInteritemSpacing = 0;
  }
  return _segmentBarLayout;
}

- (void)setSelectedIndex:(NSInteger)selectedIndex
{
  if (_selectedIndex == selectedIndex) {
    return;
  }
  _previousIndex = _selectedIndex == NSNotFound ? selectedIndex : _selectedIndex;

  NSParameterAssert(selectedIndex >= 0 && selectedIndex < self.viewControllers.count);
  UIViewController *toSelectController = [self.viewControllers objectAtIndex:selectedIndex];

  // Add selected view controller as child view controller

  if (!toSelectController.parentViewController) {
    [self addChildViewController:toSelectController];
    [self configureViewControllerFrame:toSelectController];
    [self.slideView addSubview:toSelectController.view];
    [toSelectController didMoveToParentViewController:self];
  }
  _selectedIndex = selectedIndex;
  self.slideView.backgroundColor = toSelectController.view.backgroundColor;
  if ([_delegate respondsToSelector:@selector(didSelectViewController:)]) {
    [_delegate didSelectViewController:self.selectedViewController];
  }
}

- (void)setStartIndex:(NSInteger)startIndex
{
  _startIndex = startIndex;
}

- (void)setViewControllers:(NSArray *)viewControllers
{
  // Need remove previous viewControllers
  for (UIViewController *vc in _viewControllers) {
      [vc willMoveToParentViewController:nil];
      [vc.view removeFromSuperview];
      [vc removeFromParentViewController];
      [vc didMoveToParentViewController:nil];
  }
  _viewControllers = [viewControllers copy];
  [self reset];
}

- (NSArray *)viewControllers
{
  return [_viewControllers copy];
}

- (UIViewController *)selectedViewController
{
  return self.viewControllers[self.selectedIndex];
}

#pragma mark - UICollectionViewDataSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
  if ([_dataSource respondsToSelector:@selector(numberOfSectionsInslideSegment:)]) {
    return [_dataSource numberOfSectionsInslideSegment:collectionView];
  }
  return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
  if ([_dataSource respondsToSelector:@selector(slideSegment:numberOfItemsInSection:)]) {
    return [_dataSource slideSegment:collectionView numberOfItemsInSection:section];
  }
  return self.viewControllers.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
  if ([_dataSource respondsToSelector:@selector(slideSegment:cellForItemAtIndexPath:)]) {
    return [_dataSource slideSegment:collectionView cellForItemAtIndexPath:indexPath];
  }

  JYSegmentBarItem *segmentBarItem = [collectionView dequeueReusableCellWithReuseIdentifier:segmentBarItemID
                                                                               forIndexPath:indexPath];
  UIViewController *vc = self.viewControllers[indexPath.row];
  segmentBarItem.titleLabel.text = vc.title;
  return segmentBarItem;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
  if ([_dataSource respondsToSelector:@selector(slideSegment:layout:sizeForItemAtIndexPath:)]) {
    return [_dataSource slideSegment:collectionView layout:collectionViewLayout sizeForItemAtIndexPath:indexPath];
  }
  CGSize cellSize;
  cellSize.height = self.segmentBarHeight;
  cellSize.width = self.itemWidth;
  return cellSize;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
  if (indexPath.row < 0 || indexPath.row >= self.viewControllers.count) {
    return;
  }
  if ([_delegate respondsToSelector:@selector(slideSegment:didSelectItemAtIndexPath:)]) {
    [_delegate slideSegment:collectionView didSelectItemAtIndexPath:indexPath];
  }
  [self setSelectedIndex:indexPath.row];
  [self scrollToViewWithIndex:self.selectedIndex animated:NO];
  [self segmentBarScrollToIndex:_selectedIndex animated:YES];
  [self removePreviousViewController];
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
  if (indexPath.row < 0 || indexPath.row >= self.viewControllers.count) {
    return NO;
  }

  BOOL flag = YES;
  UIViewController *vc = self.viewControllers[indexPath.row];
  if ([_delegate respondsToSelector:@selector(shouldSelectViewController:)]) {
    flag = [_delegate shouldSelectViewController:vc];
  }
  return flag;
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (scrollView == self.slideView) {
    if (self.slideView.scrollContentSizeResizing) {
      return;
    }
    CGFloat percent = scrollView.contentOffset.x / scrollView.contentSize.width;
    CGFloat destination = percent * self.viewControllers.count;
    NSInteger index = destination >= self.lastDestination ? ceilf(destination)
                                                          : floor(destination);
    CGRect frame = self.currentIndicatorFrame;

    CGRect indicatorFrame = CGRectMake(self.indicatorInsets.left, 0,
                                       self.itemWidth, self.indicatorHeight);
    CGFloat segmentBarPercent =
        fmodf(scrollView.contentOffset.x, CGRectGetWidth(self.view.frame)) /
        CGRectGetWidth(self.view.frame);

    CGPoint translation = [scrollView.panGestureRecognizer translationInView:scrollView.superview];

    if (segmentBarPercent == 0.f) {
      NSInteger currentIndex = scrollView.contentOffset.x / CGRectGetWidth(self.view.frame);
      CGRect cellFrame = [self frameForSegmentItemAtIndex:currentIndex];
      frame.origin.x = cellFrame.origin.x;
      frame.size.width = CGRectGetWidth(cellFrame);
      self.itemWidth = CGRectGetWidth(cellFrame);
    } else {
      if (translation.x > 0) {
        CGRect destItemFrame = [self frameForSegmentItemAtIndex:(ceilf(destination) - 1)];
        CGRect srcItemFrame = [self frameForSegmentItemAtIndex:ceilf(destination)];
        frame.origin.x -= (1 - segmentBarPercent) * CGRectGetWidth(destItemFrame);
        frame.size.width +=
            (1 - segmentBarPercent) *
            (CGRectGetWidth(destItemFrame) - CGRectGetWidth(srcItemFrame));
      } else {
        CGRect destItemFrame = [self frameForSegmentItemAtIndex:(floor(destination) + 1)];
        CGRect srcItemFrame = [self frameForSegmentItemAtIndex:floor(destination)];
        frame.origin.x += segmentBarPercent * srcItemFrame.size.width;
        frame.size.width += segmentBarPercent * (CGRectGetWidth(destItemFrame) -
                                                 CGRectGetWidth(srcItemFrame));
      }
    }
    indicatorFrame.size.width = frame.size.width - self.indicatorInsets.left -
                                self.indicatorInsets.right;
    self.indicatorBgView.frame = frame;
    self.indicator.frame = indicatorFrame;

    if (index >= 0 && index < self.viewControllers.count) {
      [self setSelectedIndex:index];
    }
    self.lastDestination = destination;

    if ([_delegate respondsToSelector:@selector(slideViewDidScroll:)]) {
      [_delegate slideViewDidScroll:scrollView];
    }
  } else if (scrollView == self.segmentBar) {
    if ([_delegate respondsToSelector:@selector(slideSegmentDidScroll:)]) {
      [_delegate slideSegmentDidScroll:scrollView];
    }
  }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
  self.currentIndicatorFrame = self.indicatorBgView.frame;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  if (scrollView == self.slideView) {
    [self segmentBarScrollToIndex:_selectedIndex animated:YES];
    [self removePreviousViewController];
    if ([_delegate respondsToSelector:@selector(didFullyShowViewController:)]) {
      [_delegate didFullyShowViewController:self.selectedViewController];
    }
  }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
  if (scrollView == self.slideView) {
    [self segmentBarScrollToIndex:_selectedIndex animated:YES];
    [self removePreviousViewController];
    if ([_delegate respondsToSelector:@selector(didFullyShowViewController:)]) {
      [_delegate didFullyShowViewController:self.selectedViewController];
    }
  }
}

#pragma mark - Action
- (void)scrollToViewWithIndex:(NSInteger)index animated:(BOOL)animated
{
  CGRect rect = self.slideView.bounds;
  rect.origin.x = rect.size.width * index;
  [self.slideView setContentOffset:CGPointMake(rect.origin.x, rect.origin.y) animated:animated];
  if (!animated) {
    [self segmentBarScrollToIndex:index animated:NO];
  }
  if (!animated && [_delegate respondsToSelector:@selector(didFullyShowViewController:)]) {
    [_delegate didFullyShowViewController:self.selectedViewController];
  }
}

- (void)reset
{
  _selectedIndex = NSNotFound;
  _previousIndex = NSNotFound;

  [self.segmentBar reloadData];
  
  CGSize conentSize = CGSizeMake(_slideView.bounds.size.width * self.viewControllers.count, 0);
  [_slideView setContentSize:conentSize];

  [self setSelectedIndex:self.startIndex];
  [self scrollToViewWithIndex:self.startIndex animated:NO];
  [self segmentBarScrollToIndex:self.startIndex animated:NO];
}

- (void)segmentBarScrollToIndex:(NSInteger)index animated:(BOOL)animated
{
  [self.segmentBar
      selectItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]
                   animated:animated
             scrollPosition:UICollectionViewScrollPositionCenteredHorizontally];
}

- (void)scrollToItemWithIndex:(NSInteger)index animated:(BOOL)animated
{
  [self setSelectedIndex:index];
  [self scrollToViewWithIndex:self.selectedIndex animated:animated];
  [self segmentBarScrollToIndex:self.selectedIndex animated:animated];
}

- (void)removePreviousViewController
{
  NSParameterAssert(self.previousIndex >= 0 &&
                    self.previousIndex < self.viewControllers.count);
  if (self.previousIndex == self.selectedIndex) {
    return;
  }
  UIViewController *previousViewController =
  self.viewControllers[self.previousIndex];
  if (previousViewController && previousViewController.parentViewController) {
    [previousViewController willMoveToParentViewController:nil];
    [previousViewController.view removeFromSuperview];
    [previousViewController removeFromParentViewController];
  }
}

- (void)configureViewControllerFrame:(UIViewController *)vc
{
  if (!vc) {
    return;
  }
  NSInteger index = [self.viewControllers indexOfObject:vc];
  if (index != NSNotFound && vc.parentViewController == self) {
    CGRect rect = self.slideView.bounds;
    rect.origin.x = rect.size.width * index;
    rect.origin.y = 0;
    rect.size.height -= self.slideView.contentInset.top + self.slideView.contentInset.bottom;
    vc.view.frame = rect;
  }
}

- (void)handleOrientationDidChangeNotification:(NSNotification *)notification
{
    if (self.selectedIndex == NSNotFound) {
        return;
    }
    self.slideView.scrollContentSizeResizing = YES;
    [self adjustContentSize];
    self.slideView.scrollContentSizeResizing = NO;
    [self.segmentBar reloadData];
    [self.segmentBar setNeedsLayout];
    [self.segmentBar layoutIfNeeded];
    [self configureViewControllerFrame:self.selectedViewController];
    [self scrollToViewWithIndex:self.selectedIndex animated:NO];
}

- (CGRect)frameForSegmentItemAtIndex:(NSInteger)index
{
  NSParameterAssert(index >= 0 && index < self.viewControllers.count);
  NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
  UICollectionViewLayoutAttributes *attributes = [self.segmentBar layoutAttributesForItemAtIndexPath:indexPath];
  return attributes.frame;
}

- (void)adjustContentSize
{
  CGSize conentSize = CGSizeMake(_slideView.bounds.size.width * self.viewControllers.count, 0);
  [_slideView setContentSize:conentSize];
}

@end
