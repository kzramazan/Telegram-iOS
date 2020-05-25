#import "TGMediaPickerGalleryVideoItemView.h"

#import "LegacyComponentsInternal.h"
#import "TGFont.h"
#import "TGImageUtils.h"
#import "TGStringUtils.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

#import <LegacyComponents/TGPhotoEditorUtils.h>
#import <LegacyComponents/TGObserverProxy.h>
#import <LegacyComponents/TGTimerTarget.h>
#import <LegacyComponents/TGMediaAssetImageSignals.h>
#import <LegacyComponents/TGMediaAsset.h>

#import <LegacyComponents/TGPhotoEditorInterfaceAssets.h>
#import <LegacyComponents/TGPhotoEditorAnimation.h>

#import "TGMediaPickerGalleryItem.h"
#import "TGMediaPickerGalleryVideoItem.h"

#import <LegacyComponents/TGVideoEditAdjustments.h>
#import <LegacyComponents/TGPaintingData.h>

#import <LegacyComponents/TGImageView.h>
#import <LegacyComponents/TGModernButton.h>
#import <LegacyComponents/TGMessageImageViewOverlayView.h>
#import "TGMediaPickerGalleryVideoScrubber.h"
#import "TGMediaPickerScrubberHeaderView.h"

#import "TGPhotoEditorPreviewView.h"
#import "TGPhotoEntitiesContainerView.h"
#import "TGPhotoPaintController.h"

#import <LegacyComponents/TGModernGalleryVideoView.h>
#import "TGModernGalleryVideoContentView.h"

#import <LegacyComponents/TGMenuView.h>

#import "PGPhotoEditor.h"

@interface TGMediaPickerGalleryVideoItemView() <TGMediaPickerGalleryVideoScrubberDataSource, TGMediaPickerGalleryVideoScrubberDelegate>
{
    UIView *_containerView;
    TGModernGalleryVideoContentView *_contentView;
    UIView *_playerWrapperView;
    UIView *_playerView;
    UIView *_playerContainerView;
    UIView *_curtainView;
    
    MPVolumeView *_volumeOverlayFixView;
    
    TGMenuContainerView *_tooltipContainerView;
    
    UITapGestureRecognizer *_tapGestureRecognizer;
    
    TGModernButton *_actionButton;
    TGMessageImageViewOverlayView *_progressView;
    bool _progressVisible;
    void (^_currentAvailabilityObserver)(bool);
    
    UIView *_headerView;
    UIView *_scrubberPanelView;
    TGMediaPickerGalleryVideoScrubber *_scrubberView;
    bool _wasPlayingBeforeScrubbing;
    bool _appeared;
    bool _scrubbingPanelPresented;
    bool _scrubbingPanelLocked;
    bool _shouldResetScrubber;
    
    UILabel *_fileInfoLabel;
    
    TGPhotoEditorPreviewView *_videoView;
    PGPhotoEditor *_photoEditor;
    
    UIImageView *_paintingImageView;
    UIView *_contentWrapperView;
    TGPhotoEntitiesContainerView *_entitiesContainerView;
    
    NSTimer *_positionTimer;
    TGObserverProxy *_didPlayToEndObserver;
    
    CGSize _videoDimensions;
    NSTimeInterval _videoDuration;
    
    UIImage *_lastRenderedScreenImage;
    
    SVariable *_videoDurationVar;
    SMetaDisposable *_videoDurationDisposable;
    SMetaDisposable *_playerItemDisposable;
    SMetaDisposable *_thumbnailsDisposable;
    SMetaDisposable *_adjustmentsDisposable;
    SMetaDisposable *_attributesDisposable;
    SMetaDisposable *_downloadDisposable;
    SMetaDisposable *_currentAudioSession;
    
    UIEdgeInsets _safeAreaInset;
    
    bool _requestingThumbnails;
    bool _downloadRequired;
    bool _downloading;
    bool _downloaded;
    
    bool _sendAsGif;
    bool _autoplayed;
}

@property (nonatomic, strong) TGMediaPickerGalleryVideoItem *item;

@end

@implementation TGMediaPickerGalleryVideoItemView

@dynamic item;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        _currentAudioSession = [[SMetaDisposable alloc] init];
        _playerItemDisposable = [[SMetaDisposable alloc] init];
        
        _videoDurationVar = [[SVariable alloc] init];
        _videoDurationDisposable = [[SMetaDisposable alloc] init];
        
        _adjustmentsDisposable = [[SMetaDisposable alloc] init];
        
        _containerView = [[UIView alloc] initWithFrame:self.bounds];
        _containerView.clipsToBounds = true;
        [self addSubview:_containerView];
        
        _contentView = [[TGModernGalleryVideoContentView alloc] init];
        [_containerView addSubview:_contentView];
        
        _playerWrapperView = [[UIView alloc] init];
        [_contentView addSubview:_playerWrapperView];
        
        _playerView = [[UIView alloc] init];
        _playerView.clipsToBounds = true;
        [_playerWrapperView addSubview:_playerView];
        
        _playerContainerView = [[UIView alloc] init];
        [_playerView addSubview:_playerContainerView];
        
        _imageView = [[TGModernGalleryImageItemImageView alloc] init];
        [_playerContainerView addSubview:_imageView];
        
        _paintingImageView = [[UIImageView alloc] init];
        [_playerContainerView addSubview:_paintingImageView];
        
        _contentWrapperView = [[UIView alloc] init];
        [_playerContainerView addSubview:_contentWrapperView];
        
        _entitiesContainerView = [[TGPhotoEntitiesContainerView alloc] init];
        _entitiesContainerView.hidden = true;
        _entitiesContainerView.userInteractionEnabled = false;
        [_contentWrapperView addSubview:_entitiesContainerView];
        
        _curtainView = [[UIView alloc] init];
        _curtainView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _curtainView.backgroundColor = [UIColor blackColor];
        _curtainView.hidden = true;
        [_contentView addSubview:_curtainView];
        
        _actionButton = [[TGModernButton alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        _actionButton.modernHighlight = true;
        
        CGFloat circleDiameter = 60.0f;
        static UIImage *highlightImage = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^
        {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(circleDiameter, circleDiameter), false, 0.0f);
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSetFillColorWithColor(context, UIColorRGBA(0x000000, 0.4f).CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(0.0f, 0.0f, circleDiameter, circleDiameter));
            highlightImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        });
        
        _actionButton.highlightImage = highlightImage;
        
        _progressView = [[TGMessageImageViewOverlayView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        [_progressView setRadius:60.0];
        _progressView.userInteractionEnabled = false;
        [_progressView setPlay];
        [_actionButton addSubview:_progressView];
        
        [_actionButton addTarget:self action:@selector(playPressed) forControlEvents:UIControlEventTouchUpInside];
        
        _contentView.button = _actionButton;
        [_contentView addSubview:_actionButton];
        
        TGMediaPickerScrubberHeaderView *headerView = [[TGMediaPickerScrubberHeaderView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 44)];
        _headerView = headerView;
        _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        _scrubberPanelView = [[UIView alloc] initWithFrame:CGRectMake(0, -64, _headerView.frame.size.width, 64)];
        _scrubberPanelView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _scrubberPanelView.hidden = true;
        headerView.panelView = _scrubberPanelView;
        [_headerView addSubview:_scrubberPanelView];
        
        UIView *scrubberBackgroundView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, -100.0f, _headerView.frame.size.width, 164.0f)];
        scrubberBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        scrubberBackgroundView.backgroundColor = [TGPhotoEditorInterfaceAssets toolbarTransparentBackgroundColor];
        [_scrubberPanelView addSubview:scrubberBackgroundView];
        
        _scrubberView = [[TGMediaPickerGalleryVideoScrubber alloc] initWithFrame:CGRectMake(0.0f, _headerView.frame.size.height - 44.0f, _headerView.frame.size.width, 44.0f)];
        _scrubberView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _scrubberView.dataSource = self;
        _scrubberView.delegate = self;
        headerView.scrubberView = _scrubberView;
        [_scrubberPanelView addSubview:_scrubberView];
        
        _fileInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10.0f, _scrubberPanelView.frame.size.width, 21)];
        _fileInfoLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _fileInfoLabel.backgroundColor = [UIColor clearColor];
        _fileInfoLabel.font = TGSystemFontOfSize(13.0f);
        _fileInfoLabel.textAlignment = NSTextAlignmentCenter;
        _fileInfoLabel.textColor = [UIColor whiteColor];
        
        _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTap)];
        [_contentView addGestureRecognizer:_tapGestureRecognizer];
    }
    return self;
}

- (void)dealloc
{
    [_videoDurationDisposable dispose];
    [_playerItemDisposable dispose];
    [_adjustmentsDisposable dispose];
    [_thumbnailsDisposable dispose];
    [_attributesDisposable dispose];
    [_downloadDisposable dispose];
    [self stopPlayer];
    
    [self releaseVolumeOverlay];
}

- (void)setSafeAreaInset:(UIEdgeInsets)safeAreaInset
{
    _safeAreaInset = safeAreaInset;
    [(TGMediaPickerScrubberHeaderView *)_headerView setSafeAreaInset:safeAreaInset];
}

- (void)inhibitVolumeOverlay
{
    if (_volumeOverlayFixView != nil)
        return;
    
    UIWindow *keyWindow = self.window; //[UIApplication sharedApplication].keyWindow;
    UIView *rootView = keyWindow.rootViewController.view;
    
    _volumeOverlayFixView = [[MPVolumeView alloc] initWithFrame:CGRectMake(10000, 10000, 20, 20)];
    [rootView addSubview:_volumeOverlayFixView];
}

- (void)releaseVolumeOverlay
{
    if (_volumeOverlayFixView == nil)
        return;
    
    [_volumeOverlayFixView removeFromSuperview];
    _volumeOverlayFixView = nil;
}

- (void)prepareForRecycle
{
    [super prepareForRecycle];
    
    [_videoDurationVar set:[SSignal single:nil]];
    [_videoDurationDisposable setDisposable:nil];
    
    [self _playerCleanup];
    self.isPlaying = false;
    
    _appeared = false;
    [self setScrubbingPanelApperanceLocked:false];
    [self setScrubbingPanelHidden:true animated:false];
    
    [_positionTimer invalidate];
    _positionTimer = nil;
    
    _lastRenderedScreenImage = nil;
    
    _downloaded = false;    
    _downloading = false;
    _downloadRequired = false;
    [_downloadDisposable setDisposable:nil];
    
    [self releaseVolumeOverlay];
}

+ (NSString *)_stringForDimensions:(CGSize)dimensions
{
    CGFloat longSide = MIN(dimensions.width, dimensions.height);
    if (longSide == 1080)
        return @"1080p";
    else if (longSide == 720)
        return @"720p";
    else if (longSide == 480)
        return @"480p";
    else if (longSide == 360)
        return @"360p";
    else if (longSide == 240)
        return @"240p";
    else if (longSide == 144)
        return @"144p";
    
    return [NSString stringWithFormat:@"%dx%d", (int)dimensions.width, (int)dimensions.height];
}

- (void)_setDownloadRequired
{
    _downloadRequired = true;
    [_progressView setDownload];
    
    _downloaded = false;
    if (_currentAvailabilityObserver != nil)
        _currentAvailabilityObserver(false);
}

- (void)_download
{
    if (_downloading)
        return;
    
    _downloading = true;
    
    if (_downloadDisposable == nil)
        _downloadDisposable = [[SMetaDisposable alloc] init];
    
    __weak TGMediaPickerGalleryVideoItemView *weakSelf = self;
    [_downloadDisposable setDisposable:[[[TGMediaAssetImageSignals avAssetForVideoAsset:(TGMediaAsset *)self.item.asset allowNetworkAccess:true] deliverOn:[SQueue mainQueue]] startWithNext:^(id next)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if ([next isKindOfClass:[NSNumber class]])
        {
            CGFloat value = [next doubleValue];
            [strongSelf setProgressVisible:value < 1.0f - FLT_EPSILON value:value animated:true];
        }
    } completed:^
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf setItem:strongSelf.item];
        [strongSelf->_progressView setPlay];
        
        strongSelf->_downloaded = true;
        if (strongSelf->_currentAvailabilityObserver != nil)
            strongSelf->_currentAvailabilityObserver(true);
    }]];
}

- (void)setItem:(TGMediaPickerGalleryVideoItem *)item synchronously:(bool)synchronously
{
    bool itemChanged = ![item isEqual:self.item];
    
    [super setItem:item synchronously:synchronously];
    
    if (itemChanged)
        [self _playerCleanup];
    
    _scrubberView.allowsTrimming = false;
    _videoDimensions = item.dimensions;
    _entitiesContainerView.stickersContext = item.stickersContext;
    
    __weak TGMediaPickerGalleryVideoItemView *weakSelf = self;
    [_videoDurationVar set:[[[item.durationSignal deliverOn:[SQueue mainQueue]] catch:^SSignal *(__unused id error)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf != nil && [error isKindOfClass:[NSNumber class]])
            [strongSelf _setDownloadRequired];
        
        return nil;
    }] onNext:^(__unused id next)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            strongSelf->_downloaded = true;
            if (strongSelf->_currentAvailabilityObserver != nil)
                strongSelf->_currentAvailabilityObserver(true);
        }
    }]];
    
    SSignal *imageSignal = nil;
    if (item.asset != nil)
    {
        SSignal *assetSignal = [SSignal single:nil];
        if ([item.asset isKindOfClass:[TGMediaAsset class]])
        {
            assetSignal = [TGMediaAssetImageSignals imageForAsset:(TGMediaAsset *)item.asset imageType:(item.immediateThumbnailImage != nil) ? TGMediaAssetImageTypeScreen : TGMediaAssetImageTypeFastScreen size:CGSizeMake(1280, 1280)];
        }
        else
        {
            assetSignal = [item.asset screenImageSignal:0.0];
        }
        
        imageSignal = assetSignal;
        if (item.editingContext != nil)
        {
            imageSignal = [[item.editingContext imageSignalForItem:item.editableMediaItem] mapToSignal:^SSignal *(id result)
            {
                if (result != nil)
                    return [SSignal single:result];
                else
                    return assetSignal;
            }];
        }
    }
    
    if (item.immediateThumbnailImage != nil)
    {
        SSignal *immediateSignal = [SSignal single:item.immediateThumbnailImage];
        imageSignal = imageSignal != nil ? [immediateSignal then:imageSignal] : immediateSignal;
        item.immediateThumbnailImage = nil;
    }
    
    [self.imageView setSignal:imageSignal];
    
    if (item.editingContext != nil)
    {
        SSignal *adjustmentsSignal = [item.editingContext adjustmentsSignalForItem:item.editableMediaItem];
        [_adjustmentsDisposable setDisposable:[[adjustmentsSignal deliverOn:[SQueue mainQueue]] startWithNext:^(__unused id next)
        {
            __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            [strongSelf _layoutPlayerView];
            TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[strongSelf.item.editingContext adjustmentsForItem:strongSelf.item.editableMediaItem];
            strongSelf->_paintingImageView.image = adjustments.paintingData.image;
            
            strongSelf->_sendAsGif = adjustments.sendAsGif;
            [strongSelf _mutePlayer:adjustments.sendAsGif];
            
            if (adjustments.sendAsGif || ([strongSelf itemIsLivePhoto]))
                [strongSelf setPlayButtonHidden:true animated:false];
            
            [strongSelf->_entitiesContainerView setupWithPaintingData:adjustments.paintingData];
            [strongSelf->_photoEditor importAdjustments:adjustments];
            
            if (!strongSelf.isPlaying) {
                [strongSelf->_photoEditor reprocess];
            }
        }]];
    }
    else
    {
        _sendAsGif = false;
        [self _layoutPlayerView];
    }
    
    if (!item.asFile)
        return;
    
    if (_attributesDisposable == nil)
        _attributesDisposable = [[SMetaDisposable alloc] init];
    
    _fileInfoLabel.text = nil;
    [_attributesDisposable setDisposable:[[[TGMediaAssetImageSignals fileAttributesForAsset:item.asset] deliverOn:[SQueue mainQueue]] startWithNext:^(TGMediaAssetImageFileAttributes *next)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        NSMutableArray *components = [[NSMutableArray alloc] init];
        if (next.fileName.length > 0)
            [components addObject:next.fileName.pathExtension.uppercaseString];
        if (next.fileSize > 0)
            [components addObject:[TGStringUtils stringForFileSize:next.fileSize precision:2]];
        [components addObject:[TGMediaPickerGalleryVideoItemView _stringForDimensions:next.dimensions]];
        
        strongSelf->_fileInfoLabel.text = [components componentsJoinedByString:@" • "];
    }]];
}

- (void)setIsCurrent:(bool)isCurrent
{
    if (_sendAsGif)
    {
        if (isCurrent)
        {
            if (!_autoplayed  && !self.isPlaying)
            {
                _autoplayed = true;
                [self play];
            }
        }
        else
        {
            _autoplayed = false;
        }
    }
    
    if (!isCurrent)
        [self releaseVolumeOverlay];
    
    if (!isCurrent || _scrubbingPanelPresented || _requestingThumbnails)
        return;
    
    __weak TGMediaPickerGalleryVideoItemView *weakSelf = self;
    void (^block)(void) = ^
    {
        [_videoDurationDisposable setDisposable:[[_videoDurationVar.signal deliverOn:[SQueue mainQueue]] startWithNext:^(NSNumber *next)
        {
            __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
            if (strongSelf == nil || next == nil)
                return;
            
            TGMediaPickerGalleryVideoItem *item = strongSelf.item;
            NSTimeInterval videoDuration = next.doubleValue;
            strongSelf->_videoDuration = videoDuration;
            
            strongSelf->_scrubberView.allowsTrimming = (!item.asFile && ((item.asset != nil && ![strongSelf itemIsHighFramerateVideo])) && videoDuration >= TGVideoEditMinimumTrimmableDuration);
            
            TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[item.editingContext adjustmentsForItem:item.editableMediaItem];
            if (adjustments != nil && fabs(adjustments.trimEndValue - adjustments.trimStartValue) > DBL_EPSILON)
            {
                strongSelf->_scrubberView.trimStartValue = adjustments.trimStartValue;
                strongSelf->_scrubberView.trimEndValue = adjustments.trimEndValue;
                strongSelf->_scrubberView.value = adjustments.trimStartValue;
                [strongSelf->_scrubberView setTrimApplied:(adjustments.trimStartValue > 0 || adjustments.trimEndValue < videoDuration)];
                strongSelf->_shouldResetScrubber = false;
            }
            else
            {
                strongSelf->_scrubberView.trimStartValue = 0;
                strongSelf->_scrubberView.trimEndValue = videoDuration;
                [strongSelf->_scrubberView setTrimApplied:false];
                strongSelf->_shouldResetScrubber = true;
            }
            
            [strongSelf->_scrubberView reloadData];
            if (!strongSelf->_appeared)
            {
                [strongSelf->_scrubberView resetToStart];
                strongSelf->_appeared = true;
            }
        }]];
    };
    
    if (_scrubberView.frame.size.width < FLT_EPSILON)
        TGDispatchAfter(0.05, dispatch_get_main_queue(), block);
    else
        block();
}

- (void)presentScrubbingPanelAfterReload:(bool)afterReload
{
    if (![self usePhotoBehavior])
    {
        if (afterReload)
            [_scrubberView reloadData];
        else
            [self setScrubbingPanelHidden:false animated:true];
    }
}

- (void)setScrubbingPanelApperanceLocked:(bool)locked
{
    _scrubbingPanelLocked = locked;
}

- (void)setScrubbingPanelHidden:(bool)hidden animated:(bool)animated
{
    if (_scrubbingPanelLocked)
        return;
    
    if (hidden)
    {
        if (!_scrubbingPanelPresented)
            [_scrubberView ignoreThumbnails];
        
        _scrubbingPanelPresented = false;
        
        void (^changeBlock)(void) = ^
        {
            _scrubberPanelView.frame = CGRectMake(0.0f, -64.0f - _safeAreaInset.top, _scrubberPanelView.frame.size.width, _scrubberPanelView.frame.size.height);
        };
        void (^completionBlock)(BOOL) = ^(BOOL finished)
        {
            if (finished)
                _scrubberPanelView.hidden = true;
        };
        
        if (animated)
        {
            [UIView animateWithDuration:0.3f delay:0.0f options:(7 << 16) animations:changeBlock completion:completionBlock];
        }
        else
        {
            changeBlock();
            completionBlock(true);
        }
    }
    else
    {
        if (_scrubbingPanelPresented)
            return;
        
        _scrubbingPanelPresented = true;
        
        _scrubberPanelView.hidden = false;
        [_scrubberPanelView layoutSubviews];
        [_scrubberView layoutSubviews];
        
        void (^changeBlock)(void) = ^
        {
             _scrubberPanelView.frame = CGRectMake(0.0f, 0.0f, _scrubberPanelView.frame.size.width, _scrubberPanelView.frame.size.height);
        };
        
        if (animated)
            [UIView animateWithDuration:0.3f delay:0.0f options:(7 << 16) animations:changeBlock completion:nil];
        else
            changeBlock();
    }
}

- (void)prepareForEditing
{
    [self setScrubbingPanelHidden:true animated:true];
    [self setScrubbingPanelApperanceLocked:true];
    [self setPlayButtonHidden:true animated:true];
    [self stop];
}

- (bool)usePhotoBehavior
{
    TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[self.item.editingContext adjustmentsForItem:self.item.editableMediaItem];
    if (![self itemIsLivePhoto] || adjustments.sendAsGif)
        return false;
    
    return true;
}

- (bool)itemIsLivePhoto
{
    if ([self.item.asset isKindOfClass:[TGMediaAsset class]])
        return ((TGMediaAsset *)self.item.asset).subtypes & TGMediaAssetSubtypePhotoLive;
    
    return false;
}

- (bool)itemIsHighFramerateVideo
{
    if ([self.item.asset isKindOfClass:[TGMediaAsset class]])
        return ((TGMediaAsset *)self.item.asset).subtypes & TGMediaAssetSubtypeVideoHighFrameRate;
    
    return false;
}

- (void)returnFromEditing
{
    if (![self usePhotoBehavior])
        [self setPlayButtonHidden:false animated:true];
}

- (void)setFrame:(CGRect)frame
{
    bool frameChanged = !CGRectEqualToRect(frame, self.frame);
    
    [super setFrame:frame];
    
    if (_appeared && frameChanged)
    {
        [_scrubberView resetThumbnails];
        
        [self setScrubbingPanelHidden:true animated:false];
        [_scrubberPanelView setNeedsLayout];
        [_scrubberPanelView layoutIfNeeded];
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [_scrubberView reloadThumbnails];
            [_scrubberPanelView layoutSubviews];
        });
    }
    
    if (_containerView == nil)
        return;
    
    _containerView.frame = self.bounds;
    
    [self _layoutPlayerView];
    
    _contentView.frame = (CGRect){CGPointZero, frame.size};
    
    if (_tooltipContainerView != nil && frame.size.width > frame.size.height)
    {
        [_tooltipContainerView removeFromSuperview];
        _tooltipContainerView = nil;
    }
        
}

- (void)_layoutPlayerView
{
    [_playerView pop_removeAllAnimations];
    
    TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[self.item.editingContext adjustmentsForItem:self.item.editableMediaItem];
    CGSize videoFrameSize = _videoDimensions;
    CGRect cropRect = CGRectMake(0, 0, videoFrameSize.width, videoFrameSize.height);
    UIImageOrientation orientation = UIImageOrientationUp;
    bool mirrored = false;
    if (adjustments != nil)
    {
        videoFrameSize = adjustments.cropRect.size;
        cropRect = adjustments.cropRect;
        orientation = adjustments.cropOrientation;
        mirrored = adjustments.cropMirrored;
    }
    
    _scrubberView.maximumLength = adjustments.sendAsGif ? TGVideoEditMaximumGifDuration : 0.0;
    
    [self _layoutPlayerViewWithCropRect:cropRect videoFrameSize:videoFrameSize orientation:orientation mirrored:mirrored];
}

- (void)_layoutPlayerViewWithCropRect:(CGRect)cropRect videoFrameSize:(CGSize)videoFrameSize orientation:(UIImageOrientation)orientation mirrored:(bool)mirrored
{
    CGAffineTransform transform = CGAffineTransformMakeRotation(TGRotationForOrientation(orientation));
    if (mirrored)
        transform = CGAffineTransformScale(transform, -1.0f, 1.0f);
    _playerView.transform = transform;
    
    if (orientation == UIImageOrientationLeft || orientation == UIImageOrientationRight)
        videoFrameSize = CGSizeMake(videoFrameSize.height, videoFrameSize.width);
    
    if (CGSizeEqualToSize(videoFrameSize, CGSizeZero))
        return;

    CGSize fittedSize = TGScaleToSize(videoFrameSize, self.frame.size);
    _playerWrapperView.frame = CGRectMake((_containerView.frame.size.width - fittedSize.width) / 2, (_containerView.frame.size.height - fittedSize.height) / 2, fittedSize.width, fittedSize.height);
    _playerView.frame = _playerWrapperView.bounds;
    _playerContainerView.frame = _playerView.bounds;
    
    CGFloat ratio = fittedSize.width / videoFrameSize.width;
    _imageView.frame = CGRectMake(-cropRect.origin.x * ratio, -cropRect.origin.y * ratio, _videoDimensions.width * ratio, _videoDimensions.height * ratio);
    _paintingImageView.frame = _imageView.frame;
    _videoView.frame = _imageView.frame;
    
    CGRect rect = [TGPhotoPaintController fittedCropRect:cropRect originalSize:_videoDimensions keepOriginalSize:true];
    _entitiesContainerView.frame = CGRectMake(0, 0, rect.size.width, rect.size.height);
    
    CGSize fittedOriginalSize = TGScaleToSize(_videoDimensions, [TGPhotoPaintController maximumPaintingSize]);
    CGSize rotatedSize = fittedOriginalSize;
    CGPoint centerPoint = CGPointMake(rotatedSize.width / 2.0f, rotatedSize.height / 2.0f);
    
    CGFloat scale = fittedOriginalSize.width / _videoDimensions.width;
    CGPoint offset = TGPaintSubtractPoints(centerPoint, [TGPhotoPaintController fittedCropRect:cropRect centerScale:scale]);
    
    CGPoint boundsCenter = TGPaintCenterOfRect(_contentWrapperView.bounds);
    _entitiesContainerView.center = TGPaintAddPoints(boundsCenter, offset);
    
    CGSize fittedContentSize = [TGPhotoPaintController fittedContentSize:cropRect orientation:UIImageOrientationUp originalSize:_videoDimensions];
    CGRect fittedCropRect = [TGPhotoPaintController fittedCropRect:cropRect originalSize:_videoDimensions keepOriginalSize:false];
    _contentWrapperView.frame = CGRectMake(0.0f, 0.0f, fittedContentSize.width, fittedContentSize.height);
    
    CGFloat contentScale = _playerWrapperView.bounds.size.width / fittedCropRect.size.width;
    _contentWrapperView.transform = CGAffineTransformMakeScale(contentScale, contentScale);
    _contentWrapperView.frame = CGRectMake(0.0f, 0.0f, _playerWrapperView.bounds.size.width, _playerWrapperView.bounds.size.height);
}

- (void)singleTap
{
    if (![self usePhotoBehavior])
        [self togglePlayback];
}

- (void)setIsVisible:(bool)isVisible
{
    [super setIsVisible:isVisible];
    
    if (!isVisible && _player != nil) {
        [self stopPlayer];
        [self setPlayButtonHidden:false animated:false];
    }
}

- (UIView *)headerView
{
    return _headerView;
}

- (UIView *)footerView
{
    if (((TGMediaPickerGalleryItem *)self.item).asFile)
        return _fileInfoLabel;
    
    return nil;
}

- (UIView *)transitionView
{
    return _containerView;
}

- (CGRect)transitionViewContentRect
{
    return [_imageView convertRect:_imageView.bounds toView:[self transitionView]];
}

- (UIImage *)screenImage
{
    if (_videoView != nil)
    {
        if (_lastRenderedScreenImage != nil)
            return _lastRenderedScreenImage;
        
        UIImage *image = nil;
        
        UIGraphicsBeginImageContextWithOptions(_videoView.bounds.size, true, [UIScreen mainScreen].scale);
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:_player.currentItem.asset];
        generator.appliesPreferredTrackTransform = true;
        generator.maximumSize = TGFitSize(_videoDimensions, CGSizeMake(1280.0f, 1280.0f));
        generator.requestedTimeToleranceAfter = kCMTimeZero;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        CGImageRef imageRef = [generator copyCGImageAtTime:_player.currentTime actualTime:nil error:NULL];
        image = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);

        return image;
    }
    else
    {
        return _imageView.image;
    }
}

- (UIImage *)transitionImage
{
    UIGraphicsBeginImageContextWithOptions(_playerWrapperView.bounds.size, true, 0.0f);

    _lastRenderedScreenImage = nil;
    
    if (_videoView == nil || CMTimeCompare(_player.currentTime, kCMTimeZero) == 0)
    {
        [_playerWrapperView.layer renderInContext:UIGraphicsGetCurrentContext()];
    }
    else
    {
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:_player.currentItem.asset];
        generator.appliesPreferredTrackTransform = true;
        generator.maximumSize = TGFitSize(_videoDimensions, CGSizeMake(1280.0f, 1280.0f));
        generator.requestedTimeToleranceAfter = kCMTimeZero;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        CGImageRef imageRef = [generator copyCGImageAtTime:_player.currentTime actualTime:nil error:NULL];
        
        TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[self.item.editingContext adjustmentsForItem:self.item.editableMediaItem];
        
        UIImage *renderedImage = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
        
        if (adjustments.toolsApplied) {
            renderedImage = [PGPhotoEditor resultImageForImage:renderedImage adjustments:adjustments];
        }
        _lastRenderedScreenImage = renderedImage;
         
        CGSize originalSize = _videoDimensions;
        CGRect cropRect = CGRectMake(0, 0, _videoDimensions.width, _videoDimensions.height);
        UIImageOrientation cropOrientation = UIImageOrientationUp;
        if (adjustments != nil)
        {
            cropRect = adjustments.cropRect;
            cropOrientation = adjustments.cropOrientation;
        }
        
        CGContextConcatCTM(UIGraphicsGetCurrentContext(), TGVideoCropTransformForOrientation(cropOrientation, _playerWrapperView.bounds.size, false));

        CGFloat ratio = TGOrientationIsSideward(cropOrientation, NULL) ? _playerWrapperView.bounds.size.width / cropRect.size.height : _playerWrapperView.bounds.size.width / cropRect.size.width;

        CGRect drawRect = CGRectMake(-cropRect.origin.x * ratio, -cropRect.origin.y * ratio, originalSize.width * ratio, originalSize.height * ratio);
        [_lastRenderedScreenImage drawInRect:drawRect];
                
        if (_paintingImageView.image != nil)
            [_paintingImageView.image drawInRect:drawRect];
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (CGRect)editorTransitionViewRect
{
    return [_playerWrapperView convertRect:_playerWrapperView.bounds toView:self];
}

- (void)setHiddenAsBeingEdited:(bool)hidden
{
    _curtainView.hidden = !hidden;
}

#pragma mark - 

- (void)setProgressVisible:(bool)progressVisible value:(CGFloat)value animated:(bool)animated
{
    _progressVisible = progressVisible;
    
    if (progressVisible && _progressView == nil)
    {
        _progressView = [[TGMessageImageViewOverlayView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 60.0f, 60.0f)];
        [_progressView setRadius:60.0];
        _progressView.userInteractionEnabled = false;
        
        _progressView.frame = (CGRect){{CGFloor((self.frame.size.width - _progressView.frame.size.width) / 2.0f), CGFloor((self.frame.size.height - _progressView.frame.size.height) / 2.0f)}, _progressView.frame.size};
    }
    
    if (progressVisible)
    {
        _progressView.alpha = 1.0f;
    }
    else if (_progressView.superview != nil)
    {
        if (animated)
        {
            [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^
             {
                 _progressView.alpha = 0.0f;
             } completion:^(BOOL finished)
             {
                 if (finished)
                     [_progressView removeFromSuperview];
             }];
        }
        else
            [_progressView removeFromSuperview];
    }
    
    [_progressView setProgress:value cancelEnabled:false animated:animated];
}

- (SSignal *)contentAvailabilityStateSignal
{
    __weak TGMediaPickerGalleryVideoItemView *weakSelf = self;
    return [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[strongSelf.item.editingContext adjustmentsForItem:strongSelf.item.editableMediaItem];
            
            bool available = strongSelf->_downloaded || ([strongSelf itemIsLivePhoto] && !adjustments.sendAsGif);
            [subscriber putNext:@(available)];
            strongSelf->_currentAvailabilityObserver = ^(bool available)
            {
                [subscriber putNext:@(available)];
            };
        }
        
        return nil;
    }];
}

#pragma mark - Player

- (void)setPlayButtonHidden:(bool)hidden animated:(bool)animated
{
    if (animated)
    {
        _actionButton.hidden = false;
        [UIView animateWithDuration:0.15f animations:^
        {
            _actionButton.alpha = hidden ? 0.0f : 1.0f;
        } completion:^(BOOL finished)
        {
            if (finished)
                _actionButton.hidden = hidden;
        }];
    }
    else
    {
        _actionButton.alpha = hidden ? 0.0f : 1.0f;
        _actionButton.hidden = hidden;
    }
}

- (void)setIsPlaying:(bool)isPlaying
{
    _isPlaying = isPlaying;
    
    if (isPlaying)
        [self setPlayButtonHidden:true animated:true];
}

- (void)_playerCleanup
{
    [self stopPlayer];
    
    _videoDimensions = CGSizeZero;
    
    [_imageView reset];
    [self setPlayButtonHidden:false animated:false];
}

- (void)stopPlayer
{
    if (_player != nil)
    {
        _didPlayToEndObserver = nil;
        
        [_player removeObserver:self forKeyPath:@"rate" context:nil];
        
        [_player pause];
        _player = nil;
    }
    
    if (_videoView != nil)
    {
        SMetaDisposable *currentAudioSession = _currentAudioSession;
//        if (currentAudioSession)
//        {
//            _videoView.deallocBlock = ^
//            {
//                [[SQueue concurrentDefaultQueue] dispatch:^
//                {
//                    [currentAudioSession setDisposable:nil];
//                }];
//            };
//        }
//        [_videoView cleanupPlayer];
        _photoEditor.previewOutput = nil;
        
        [_videoView removeFromSuperview];
        _videoView = nil;
        
        [_photoEditor cleanup];
        _photoEditor = nil;
    }

    self.isPlaying = false;
    [_scrubberView setIsPlaying:false];
    [_scrubberView resetToStart];
    
    [_positionTimer invalidate];
    _positionTimer = nil;
}

- (void)preparePlayerAndPlay:(bool)play
{
    __weak TGMediaPickerGalleryVideoItemView *weakSelf = self;
    [[SQueue concurrentDefaultQueue] dispatch:^
    {
        [_currentAudioSession setDisposable:[[LegacyComponentsGlobals provider] requestAudioSession:TGAudioSessionTypePlayVideo interrupted:^
        {
            TGDispatchOnMainThread(^
            {
                __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
                if (strongSelf != nil)
                    [strongSelf pausePressed];
            });
        }]];
    }];
    
    [self inhibitVolumeOverlay];
    
    SSignal *itemSignal = nil;
    if ([self.item.asset isKindOfClass:[TGMediaAsset class]])
        itemSignal = [TGMediaAssetImageSignals playerItemForVideoAsset:(TGMediaAsset *)self.item.asset];
    else if (self.item.avAsset != nil)
        itemSignal = [SSignal single:[AVPlayerItem playerItemWithAsset:self.item.avAsset]];
    
    [_playerItemDisposable setDisposable:[[itemSignal deliverOn:[SQueue mainQueue]] startWithNext:^(AVPlayerItem *playerItem)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        strongSelf->_player = [AVPlayer playerWithPlayerItem:playerItem];
        strongSelf->_player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        [strongSelf->_player addObserver:strongSelf forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
        
        if (!strongSelf->_downloaded)
        {
            strongSelf->_downloaded = true;
            
            [strongSelf->_videoDurationVar set:[SSignal single:@(CMTimeGetSeconds(playerItem.asset.duration))]];
            
            if (strongSelf->_currentAvailabilityObserver != nil)
                strongSelf->_currentAvailabilityObserver(true);
        }
        
        strongSelf->_didPlayToEndObserver = [[TGObserverProxy alloc] initWithTarget:strongSelf targetSelector:@selector(playerItemDidPlayToEndTime:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
                
        TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[strongSelf.item.editingContext adjustmentsForItem:strongSelf.item.editableMediaItem];
        
        strongSelf->_videoView = [[TGPhotoEditorPreviewView alloc] initWithFrame:strongSelf->_imageView.frame];
        strongSelf->_videoView.customTouchDownHandling = true;
        strongSelf->_videoView.userInteractionEnabled = false;
        [strongSelf->_playerContainerView insertSubview:strongSelf->_videoView belowSubview:strongSelf->_paintingImageView];
        
        strongSelf->_entitiesContainerView.hidden = false;
        
        [strongSelf->_videoView setNeedsTransitionIn];
        [strongSelf->_videoView performTransitionInIfNeeded];
        
        strongSelf->_photoEditor = [[PGPhotoEditor alloc] initWithOriginalSize:strongSelf->_videoDimensions adjustments:adjustments forVideo:true enableStickers:true];
        strongSelf->_photoEditor.previewOutput = strongSelf->_videoView;
        [strongSelf->_photoEditor setPlayerItem:playerItem];
        [strongSelf->_photoEditor processAnimated:false completion:nil];
        
        [strongSelf _seekToPosition:adjustments.trimStartValue manual:false];
        if (adjustments.trimEndValue > DBL_EPSILON)
            [strongSelf updatePlayerRange:adjustments.trimEndValue];
        
        if (play)
        {
            strongSelf.isPlaying = true;
            [strongSelf->_player play];
        }
        
        strongSelf->_positionTimer = [TGTimerTarget scheduledMainThreadTimerWithTarget:self action:@selector(positionTimerEvent) interval:0.25 repeat:true];
        [strongSelf positionTimerEvent];
        
        [strongSelf _mutePlayer:strongSelf->_sendAsGif];
    }]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)__unused change context:(void *)__unused context
{
    if (object == _player && [keyPath isEqualToString:@"rate"])
    {
        if (_player.rate > FLT_EPSILON)
            [_scrubberView setIsPlaying:true];
        else
            [_scrubberView setIsPlaying:false];
    }
}

- (void)playPressed
{
    if (_downloadRequired)
        [self _download];
    else
        [self play];
}

- (void)play
{
    if (_player == nil)
    {
        [self preparePlayerAndPlay:true];
    }
    else
    {
        self.isPlaying = true;
        
        NSTimeInterval remaining = fabs(_scrubberView.trimEndValue - CMTimeGetSeconds(_player.currentTime));
        if (remaining < 0.5)
        {
            [self _seekToPosition:_scrubberView.trimStartValue manual:false];
            [_scrubberView setValue:_scrubberView.trimStartValue resetPosition:true];
        }
        
        [_player play];
        
        _positionTimer = [TGTimerTarget scheduledMainThreadTimerWithTarget:self action:@selector(positionTimerEvent) interval:0.25 repeat:true];
        [self positionTimerEvent];
    }
}

- (void)playIfAvailable
{
    if (!_downloadRequired)
        [self play];
}

- (void)pausePressed
{
    [self setPlayButtonHidden:false animated:true];
    [self stop];
}

- (void)stop
{
    self.isPlaying = false;
    [_player pause];
    
    [_positionTimer invalidate];
    _positionTimer = nil;
}

- (void)togglePlayback
{
    if (self.isPlaying)
        [self pausePressed];
    else
        [self playPressed];
}

- (void)playerItemDidPlayToEndTime:(NSNotification *)__unused notification
{
    if (!_sendAsGif)
    {
        self.isPlaying = false;
        [_player pause];
    
        if (![self usePhotoBehavior])
            [self setPlayButtonHidden:false animated:true];
        
        [_positionTimer invalidate];
        _positionTimer = nil;
        
        [_scrubberView resetToStart];
    }
    else
    {
        [_scrubberView setValue:_scrubberView.trimStartValue resetPosition:true];
    }
    
    [self _seekToPosition:_scrubberView.trimStartValue manual:false];
}

- (void)positionTimerEvent
{
    [self updatePositionAndForceStartTime:false];
}

- (void)updatePositionAndForceStartTime:(bool)forceStartTime
{
    NSTimeInterval value = forceStartTime ? _scrubberView.trimStartValue : CMTimeGetSeconds(_player.currentItem.currentTime);
    [_scrubberView setValue:value];
}

- (void)_seekToPosition:(NSTimeInterval)position manual:(bool)__unused manual
{
    CMTime targetTime = CMTimeMakeWithSeconds(position, NSEC_PER_SEC);
    [self.player.currentItem seekToTime:targetTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

#pragma mark - Video Scrubber Data Source & Delegate

#pragma mark Scrubbing

- (NSTimeInterval)videoScrubberDuration:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    return _videoDuration;
}

- (CGFloat)videoScrubberThumbnailAspectRatio:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    if (CGSizeEqualToSize(_videoDimensions, CGSizeZero))
        return 1.0f;
    
    return _videoDimensions.width / _videoDimensions.height;
}

- (void)videoScrubberDidBeginScrubbing:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    if (_player == nil)
        [self preparePlayerAndPlay:false];
    else
        _wasPlayingBeforeScrubbing = self.isPlaying;
    
    [self pausePressed];
    
    [self setPlayButtonHidden:true animated:false];
}

- (void)videoScrubberDidEndScrubbing:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    if (_wasPlayingBeforeScrubbing) {
        [self play];
    } else {
        [self setPlayButtonHidden:false animated:true];
    }
}

- (void)videoScrubber:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber valueDidChange:(NSTimeInterval)position
{
    [self _seekToPosition:position manual:true];
}

#pragma mark Trimming

- (bool)hasTrimming
{
    return _scrubberView.hasTrimming;
}

- (CMTimeRange)trimRange
{
    return CMTimeRangeMake(CMTimeMakeWithSeconds(_scrubberView.trimStartValue , NSEC_PER_SEC), CMTimeMakeWithSeconds((_scrubberView.trimEndValue - _scrubberView.trimStartValue), NSEC_PER_SEC));
}

- (void)videoScrubberDidBeginEditing:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    if (_player == nil)
        [self preparePlayerAndPlay:false];
    
    [self pausePressed];
    
    [self setPlayButtonHidden:true animated:false];
}

- (void)videoScrubberDidEndEditing:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    _shouldResetScrubber = false;
    [self updatePlayerRange:videoScrubber.trimEndValue];
    [self updateEditAdjusments];
    
    [self setPlayButtonHidden:false animated:true];
}

- (void)videoScrubber:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber editingStartValueDidChange:(NSTimeInterval)startValue
{
    [self _seekToPosition:startValue manual:true];
}

- (void)videoScrubber:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber editingEndValueDidChange:(NSTimeInterval)endValue
{
    [self _seekToPosition:endValue manual:true];
}

- (void)updatePlayerRange:(NSTimeInterval)trimEndValue
{
    _player.currentItem.forwardPlaybackEndTime = CMTimeMakeWithSeconds(trimEndValue, NSEC_PER_SEC);
}

#pragma mark - Edit Adjustments

- (void)toggleSendAsGif
{
    TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[self.item.editingContext adjustmentsForItem:self.item.editableMediaItem];
    CGSize videoFrameSize = _videoDimensions;
    CGRect cropRect = CGRectMake(0, 0, videoFrameSize.width, videoFrameSize.height);
    NSTimeInterval trimStartValue = 0.0;
    NSTimeInterval trimEndValue = _videoDuration;
    if (adjustments != nil)
    {
        videoFrameSize = adjustments.cropRect.size;
        cropRect = adjustments.cropRect;
        
        if (fabs(adjustments.trimEndValue - adjustments.trimStartValue) > DBL_EPSILON)
        {
            trimStartValue = adjustments.trimStartValue;
            trimEndValue = adjustments.trimEndValue;
        }
    }
    NSTimeInterval trimDuration = trimEndValue - trimStartValue;
    
    bool sendAsGif = !adjustments.sendAsGif;
    if (sendAsGif && _scrubberView.allowsTrimming)
    {
        if (trimDuration > TGVideoEditMaximumGifDuration)
        {
            trimEndValue = trimStartValue + TGVideoEditMaximumGifDuration;
            
            if (_scrubberView.value > trimEndValue)
            {
                [self stop];
                [_scrubberView setValue:_scrubberView.trimStartValue resetPosition:true];
                [self _seekToPosition:_scrubberView.value manual:true];
            }
            
            _scrubberView.trimStartValue = trimStartValue;
            _scrubberView.trimEndValue = trimEndValue;
            [_scrubberView setTrimApplied:true];
            [self updatePlayerRange:trimEndValue];
        }
    }
    else if (_shouldResetScrubber)
    {
        trimStartValue = 0.0;
        trimEndValue = _videoDuration;
        
        _scrubberView.trimStartValue = trimStartValue;
        _scrubberView.trimEndValue = trimEndValue;
        
        [_scrubberView setTrimApplied:false];
        [self updatePlayerRange:trimEndValue];
    }
    
    TGVideoEditAdjustments *updatedAdjustments = [TGVideoEditAdjustments editAdjustmentsWithOriginalSize:_videoDimensions cropRect:cropRect cropOrientation:adjustments.cropOrientation cropLockedAspectRatio:adjustments.cropLockedAspectRatio cropMirrored:adjustments.cropMirrored trimStartValue:trimStartValue trimEndValue:trimEndValue toolValues:adjustments.toolValues paintingData:adjustments.paintingData sendAsGif:sendAsGif preset:adjustments.preset];
    [self.item.editingContext setAdjustments:updatedAdjustments forItem:self.item.editableMediaItem];
    
    if (sendAsGif)
    {
        if (UIInterfaceOrientationIsPortrait([[LegacyComponentsGlobals provider] applicationStatusBarOrientation]))
        {
            UIView *parentView = [self.delegate itemViewDidRequestInterfaceView:self];
            
            _tooltipContainerView = [[TGMenuContainerView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, parentView.frame.size.width, parentView.frame.size.height)];
            [parentView addSubview:_tooltipContainerView];
            
            NSMutableArray *actions = [[NSMutableArray alloc] init];
            NSString *text = [self itemIsLivePhoto] ? TGLocalized(@"MediaPicker.LivePhotoDescription") : TGLocalized(@"MediaPicker.VideoMuteDescription");
            [actions addObject:@{@"title":text}];
            _tooltipContainerView.menuView.forceArrowOnTop = true;
            _tooltipContainerView.menuView.multiline = true;
            [_tooltipContainerView.menuView setButtonsAndActions:actions watcherHandle:nil];
            _tooltipContainerView.menuView.buttonHighlightDisabled = true;
            [_tooltipContainerView.menuView sizeToFit];
        
            CGRect iconViewFrame = CGRectMake(12, 188 + _safeAreaInset.top, 40, 40);
            [_tooltipContainerView showMenuFromRect:iconViewFrame animated:false];
        }
        
        if (self.item.selectionContext != nil)
            [self.item.selectionContext setItem:self.item.selectableMediaItem selected:true];
        
        if (!self.isPlaying)
            [self play];
    }
    
    [self _mutePlayer:sendAsGif];
}

- (void)_mutePlayer:(bool)mute
{
    if (iosMajorVersion() >= 7)
        _player.muted = mute;
}

- (void)updateEditAdjusments
{
    TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[self.item.editingContext adjustmentsForItem:self.item.editableMediaItem];
    
    if (adjustments == nil || fabs(_scrubberView.trimStartValue - adjustments.trimStartValue) > DBL_EPSILON || fabs(_scrubberView.trimEndValue - adjustments.trimEndValue) > DBL_EPSILON)
    {
        if (fabs(_scrubberView.trimStartValue - adjustments.trimStartValue) > DBL_EPSILON)
        {
            [[SQueue concurrentDefaultQueue] dispatch:^
            {
                AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:_player.currentItem.asset];
                generator.appliesPreferredTrackTransform = true;
                generator.maximumSize = TGFitSize(_videoDimensions, CGSizeMake(1280.0f, 1280.0f));
                generator.requestedTimeToleranceAfter = kCMTimeZero;
                generator.requestedTimeToleranceBefore = kCMTimeZero;
                CGImageRef imageRef = [generator copyCGImageAtTime:_player.currentTime actualTime:nil error:NULL];
                UIImage *image = [UIImage imageWithCGImage:imageRef];
                CGImageRelease(imageRef);
                
                CGSize thumbnailSize = TGPhotoThumbnailSizeForCurrentScreen();
                thumbnailSize.width = CGCeil(thumbnailSize.width);
                thumbnailSize.height = CGCeil(thumbnailSize.height);
                
                CGSize fillSize = TGScaleToFillSize(_videoDimensions, thumbnailSize);
                
                UIImage *thumbnailImage = nil;
                
                UIGraphicsBeginImageContextWithOptions(fillSize, true, 0.0f);
                CGContextRef context = UIGraphicsGetCurrentContext();
                CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
                
                [image drawInRect:CGRectMake(0, 0, fillSize.width, fillSize.height)];
                
                if (_paintingImageView.image != nil)
                    [_paintingImageView.image drawInRect:CGRectMake(0, 0, fillSize.width, fillSize.height)];
                
                thumbnailImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                
                [self.item.editingContext setImage:image thumbnailImage:thumbnailImage forItem:self.item.editableMediaItem synchronous:true];
            }];
        }
        else if (_scrubberView.trimStartValue < DBL_EPSILON)
        {
            [self.item.editingContext setImage:nil thumbnailImage:nil forItem:self.item.editableMediaItem synchronous:true];
        }
        
        CGRect cropRect = (adjustments != nil) ? adjustments.cropRect : CGRectMake(0, 0, _videoDimensions.width, _videoDimensions.height);
        UIImageOrientation cropOrientation = (adjustments != nil) ? adjustments.cropOrientation : UIImageOrientationUp;
        CGFloat cropLockedAspectRatio = (adjustments != nil) ? adjustments.cropLockedAspectRatio : 0.0f;
        
        TGVideoEditAdjustments *updatedAdjustments = [TGVideoEditAdjustments editAdjustmentsWithOriginalSize:_videoDimensions cropRect:cropRect cropOrientation:cropOrientation cropLockedAspectRatio:cropLockedAspectRatio cropMirrored:adjustments.cropMirrored trimStartValue:_scrubberView.trimStartValue trimEndValue:_scrubberView.trimEndValue toolValues:adjustments.toolValues paintingData:adjustments.paintingData sendAsGif:adjustments.sendAsGif preset:adjustments.preset];
        
        [self.item.editingContext setAdjustments:updatedAdjustments forItem:self.item.editableMediaItem];
    }
}

#pragma mark Thumbnails

- (NSArray *)videoScrubber:(TGMediaPickerGalleryVideoScrubber *)videoScrubber evenlySpacedTimestamps:(NSInteger)count startingAt:(NSTimeInterval)startTimestamp endingAt:(NSTimeInterval)endTimestamp
{
    if (endTimestamp < startTimestamp)
        return nil;
    
    if (count == 0)
        return nil;

    NSTimeInterval duration = [self videoScrubberDuration:videoScrubber];
    if (endTimestamp > duration)
        endTimestamp = duration;
    
    NSTimeInterval interval = (endTimestamp - startTimestamp) / count;
    
    NSMutableArray *timestamps = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < count; i++)
        [timestamps addObject:@(startTimestamp + i * interval)];
    
    return timestamps;
}

- (void)videoScrubber:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber requestThumbnailImagesForTimestamps:(NSArray *)timestamps size:(CGSize)size isSummaryThumbnails:(bool)isSummaryThumbnails
{
    if (timestamps.count == 0)
        return;
    
    AVAsset *avAsset = self.item.avAsset ?: _player.currentItem.asset;
    TGMediaEditingContext *editingContext = self.item.editingContext;
    id<TGMediaEditableItem> editableItem = self.item.editableMediaItem;
    
    SSignal *thumbnailsSignal = nil;
    if ([self.item.asset isKindOfClass:[TGMediaAsset class]] && ![self itemIsLivePhoto])
        thumbnailsSignal = [TGMediaAssetImageSignals videoThumbnailsForAsset:self.item.asset size:size timestamps:timestamps];
    else if (avAsset != nil)
        thumbnailsSignal = [TGMediaAssetImageSignals videoThumbnailsForAVAsset:avAsset size:size timestamps:timestamps];

    _requestingThumbnails = true;
    
    __weak TGMediaPickerGalleryVideoItemView *weakSelf = self;
    [_thumbnailsDisposable setDisposable:[[[thumbnailsSignal map:^NSArray *(NSArray *images) {
        id<TGMediaEditAdjustments> adjustments = [editingContext adjustmentsForItem:editableItem];
        if (adjustments.toolsApplied) {
            NSMutableArray *editedImages = [[NSMutableArray alloc] init];
            PGPhotoEditor *editor = [[PGPhotoEditor alloc] initWithOriginalSize:adjustments.originalSize adjustments:adjustments forVideo:false enableStickers:true];
            editor.standalone = true;
            for (UIImage *image in images) {
                [editor setImage:image forCropRect:adjustments.cropRect cropRotation:0.0 cropOrientation:adjustments.cropOrientation cropMirrored:adjustments.cropMirrored fullSize:false];
                UIImage *resultImage = editor.currentResultImage;
                if (resultImage != nil) {
                    [editedImages addObject:resultImage];
                } else {
                    [editedImages addObject:image];
                }
            }
            return editedImages;
        } else {
            return images;
        }
    }] deliverOn:[SQueue mainQueue]] startWithNext:^(NSArray *images)
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [images enumerateObjectsUsingBlock:^(UIImage *image, NSUInteger index, __unused BOOL *stop)
        {
            if (index < timestamps.count)
                [strongSelf->_scrubberView setThumbnailImage:image forTimestamp:[timestamps[index] doubleValue] isSummaryThubmnail:isSummaryThumbnails];
        }];
    } completed:^
    {
        __strong TGMediaPickerGalleryVideoItemView *strongSelf = weakSelf;
        if (strongSelf != nil)
            strongSelf->_requestingThumbnails = false;
    }]];
}

- (void)videoScrubberDidFinishRequestingThumbnails:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    _requestingThumbnails = false;
    
    [self setScrubbingPanelHidden:false animated:true];
}

- (void)videoScrubberDidCancelRequestingThumbnails:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber
{
    _requestingThumbnails = false;
}

- (CGSize)videoScrubberOriginalSize:(TGMediaPickerGalleryVideoScrubber *)__unused videoScrubber cropRect:(CGRect *)cropRect cropOrientation:(UIImageOrientation *)cropOrientation cropMirrored:(bool *)cropMirrored
{
    TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[self.item.editingContext adjustmentsForItem:self.item.editableMediaItem];
    if (cropRect != NULL)
        *cropRect = (adjustments != nil) ? adjustments.cropRect : CGRectMake(0, 0, _videoDimensions.width, _videoDimensions.height);
    
    if (cropOrientation != NULL)
        *cropOrientation = (adjustments != nil) ? adjustments.cropOrientation : UIImageOrientationUp;
    
    if (cropMirrored != NULL)
        *cropMirrored = adjustments.cropMirrored;
    
    return _videoDimensions;
}

@end
