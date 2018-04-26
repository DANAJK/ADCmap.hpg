//
//  ADCmapFilter.m
//  ADCmap
//
//  Copyright (c) 2010 Brian. All rights reserved.
//
//


#import "ADCmapFilter.h"
#import "Horos/Wait.h"

#include "Horos/Notifications.h"
// To Do List:
//  -Add "help" buttons
//  -List image number, b-value for user.
//  -Gray-out "Calculate" button unless enough b-values?
//   KYUNG: I just added "gray-out" funtionality using KVC. 
//			Please look at "enableButton"!
//  -Sort the b-values up front to simplify "non-neg" stuff.
//


#pragma mark-
#pragma mark Initialization Functions

@implementation ADCmapFilter

- (void) initPlugin
{
	//NSLog(@"ADCmap Plugin Initiated.");
}


- (long) filterImage:(NSString*) menuName
{
	NSString *msgstring;
	
    NSLog(@"ADCmapFilter filterImage started.");

	enableButton = YES;

	nbvalues = [viewerController maxMovieIndex];  // Initially get all possible b values from 4D viewer.

	//[bValueTable setDataSource:self];		// Set data-source, probably already done in IB.
	
	// This Plugin gets b-values from DICOM header (GE) and then calculates ADC map from 4D viewer.
	
    if (nbvalues >= 2) {

		//NSRunInformationalAlertPanel(@"ADC map:  (Test Version).",@"Currently expects b=600 and b=0 images - later will read this info from DICOM fields.",@"Continue", nil, nil);

		// Initialize and show window.
		//window = [[NSWindowController alloc] initWithWindowNibName:@"ADCwindow" owner:self];
		//[window showWindow:self];

		// Initialize and show window.
		[NSBundle loadNibNamed:@"ADCwindow" owner:self];
		//[NSApp beginSheet: ADCwindow 
		//   modalForWindow: [NSApp keyWindow] 
		//	modalDelegate: self 
		//   didEndSelector: nil 
		//	  contextInfo: nil];
		
		// Initialize threshold value
		threshold = 0;
		[thresholdField setStringValue:[NSString stringWithFormat:@"%g",threshold]];

        showresidual=1;
        
		// Initialize initial-guess values (mm^2/s)
		initFp = 20;
		[initFpField setStringValue:[NSString stringWithFormat:@"%g",initFp]];
		initDt = 0.001;
		[initDtField setStringValue:[NSString stringWithFormat:@"%g",initDt]];
		initDp = 0.02;
		[initDpField setStringValue:[NSString stringWithFormat:@"%g",initDp]];
        ivimCutoff = 200;
        [ivimCutoffField setStringValue:[NSString stringWithFormat:@"%g",ivimCutoff]];
		
		// Check number of b-values, and limit if necessary.
		if (nbvalues > MAXNBVALUES) {
			msgstring = [[NSString alloc] initWithFormat:
						 @"Found %d B-Values, using only %d.",nbvalues, MAXNBVALUES ];
			NSRunInformationalAlertPanel(@"ADCmap: ", msgstring, @"OK", nil, nil);
			nbvalues = MAXNBVALUES;
		}
		
		// Get x,y,z size for 3D/multislice images at each b-value (assume they are the same)
		zsize = [[viewerController pixList:0] count];							// #slices
		DCMPix *curPix = [[ viewerController pixList:0] objectAtIndex:0];		// Get first slice, to get x,y sizes.
		nxypts = [curPix pwidth] * [curPix pheight];							// #pts per slice
		
		
		// Try to Get B values from DICOM header.  (May vary with vendor...)
		[self getBValues];
		
		[bValueTable reloadData];
	
	} else {
		NSRunInformationalAlertPanel(@"Error:",@"ADC map requires 2 series/echoes/b-values in 4D viewer", @"OK", nil, nil);
	}
	
    // roiImageList is from "current slice" & "current time point"
	imageView = [viewerController imageView];
	roiImageList = [[viewerController roiList:[viewerController curMovieIndex]] objectAtIndex: [imageView curImage]];
    
    [self drawGraph:self];
    
    
	return 0;		// Not sure what else we should do here?!
    

}


- (void) getBValues
//  Attempt to read b values from DICOM header.  
//  This is be tricky with different vendors, and the fact that
//  for a given vendor, there are often different ways these are
//  encoded.
{
	// This site helps:  http://wiki.na-mic.org/Wiki/index.php/NAMIC_Wiki:DTI:DICOM_for_DWI_and_DTI#DICOM_for_DWI
	//
	DCMObject *dcmObject;
	DCMPix *thisPix;
	NSString *vendor;
	int count;
    double bvaldoubleprec;
	
	// Get Vendor
	thisPix	  = [[ viewerController pixList:0] objectAtIndex:0];
	dcmObject = [DCMObject objectWithContentsOfFile:[thisPix sourceFile] decodingPixelData:NO];
	vendor = [[[dcmObject attributeForTag:[DCMAttributeTag tagWithTagString:@"0008,0070"]] value] description];
	//NSRunInformationalAlertPanel(@"Vendor:",vendor, @"OK", nil, nil);
	NSLog(@"Vendor is %@",vendor);
	
	NSString *bvaltag;
	for (count=0; count < nbvalues; count++) {
		thisPix	  = [[ viewerController pixList:count] objectAtIndex:0];
		dcmObject = [DCMObject objectWithContentsOfFile:[thisPix sourceFile] decodingPixelData:NO];
		// Read the b-value tag, based on vendor.
		if ([vendor hasPrefix:@"GE"]) {			// GE (See below also.)
			bvaltag = [NSString stringWithFormat:@"0043,1039"];
            // GE seems to encode multiple b-value scans with 1e9 added to bvalue.
            // This seems to be addressed below.
        }
		else if ([vendor hasPrefix:@"S"]) {		// Siemens
			// Note web is 0019,000c, but images seem to show 0019,100c 
			bvaltag = [NSString stringWithFormat:@"0019,100C"];
		}
		// Based on Geoff Charles-Edwards' sample images Jan 5.  Philips seems to follow 0018,9087 *AND* 2001,1003
		else if ([vendor hasPrefix:@"P"]) {		// Philips 
			bvaltag = [NSString stringWithFormat:@"2001,1003"];
		}
		else {									// DICOM Recommendation (Note different from all 3 above!!)
			bvaltag = [NSString stringWithFormat:@"0018,9087"];
		}
		NSLog(@"Vendor is %@, bvalue tag is %@",vendor,bvaltag);
		NSLog(@"B value is %12g",bvaldoubleprec);
        
		bvaldoubleprec = [[[[dcmObject attributeForTag:[DCMAttributeTag tagWithTagString:bvaltag]] value] description] doubleValue]; 
        // GE seems to encode multiple b-value scans with 1e9 added to bvalue.
        // Need double precision to capture/remove this, hence bvaldoubleprec.
      
        if (bvaldoubleprec>=1000000000) {      
            bvaldoubleprec -= 1000000000;
            
        }
        bvals[count] = (float) bvaldoubleprec;
	}
}


- (void) awakeFromNib
{
    NSLog(@"ADCmapFilter awakeFromNib");
	[[NSNotificationCenter defaultCenter] addObserver: self 
											 selector: @selector(textChanged:) 
												 name: NSTextViewDidChangeTypingAttributesNotification 
											   object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self 
											 selector: @selector(roiChanged:) 
												 name: OsirixROIChangeNotification 
											   object: nil];
    
	//Set window to always be on top
	[ADCwindow setLevel:NSFloatingWindowLevel];

}	

#pragma mark-
#pragma mark GUI Response Functions

-(void)roiChanged:(NSNotification *) note
{	
	NSLog(@"ROI Changed!");
    roiImageList = [[viewerController roiList:[viewerController curMovieIndex]] objectAtIndex: [imageView curImage]];

	if( ([[note name] isEqualToString:@"roiChange"]) && ([[viewerController roiList] count ]>0))
	{
		//NSLog(@"name is %@",[note name]);
        [self drawGraph: self];	
	}
}


- (IBAction)updateThreshold:(id)sender
// Updates the threshold value when set by user in GUI.
{
	float threshVal = (float)([thresholdField floatValue]);
	if ((threshVal > 0) && (threshVal <=100)) 
		threshold = (float)((int)(threshVal*10))/10.0;
	else 
		threshold = 0.0;
	
	[thresholdField setStringValue:[NSString stringWithFormat:@"%g",threshold]];
}

- (IBAction)updateSynthBValue:(id)sender
// Updates the B-value for an image to synthesize when changed by user in GUI.
{
	//NSLog(@"Synthesize Field Length = %u",[[synthBField stringValue] length]);
	
	if (([[synthBField stringValue] length] > 0) && ([synthBField floatValue] >=0 )) 
		synthbvalue = [synthBField floatValue];
	else 
		synthbvalue = -1;		// Skip (don't synthesize an image)
	NSLog(@"Synthesize B value = %g",synthbvalue);

}

- (IBAction)updateInitGuesses:(id)sender
// Updates the initial-guess values for biexponential fitting.
{
	
	if (([[initFpField stringValue] length] > 0) && ([initFpField floatValue] >=0 )) 
		initFp = [initFpField floatValue]/100.0;  // Convert from percent.
	if (([[initDtField stringValue] length] > 0) && ([initDtField floatValue] >=0 )) 
		initDt = [initDtField floatValue];
	if (([[initDpField stringValue] length] > 0) && ([initDpField floatValue] >=0 )) 
		initDp = [initDpField floatValue];    
}

- (IBAction)updateIVIMCutoff:(id)sender
{
    if (([[ivimCutoffField stringValue] length] > 0) && ([ivimCutoffField floatValue] >=0 ))
		ivimCutoff = [ivimCutoffField floatValue];
    [self drawGraph:self];
}

- (IBAction) negateBvalues:(id)sender
{
    int count;
    for (count=0; count < nbvalues; count++) {
        bvals[count] = -bvals[count];
    }
    
    [bValueTable reloadData];
    [self drawGraph:self];
}

- (IBAction) negateSelBvalues:(id)sender
// Negate b values for selected rows in table.
{
    //NSLog(@"%ld Rows Selected",(long)[bValueTable numberOfSelectedRows]);
    int count;
    for (count = 0; count < nbvalues; count++) {
        if ([[bValueTable selectedRowIndexes] containsIndex:count])
            bvals[count]=-bvals[count];
    }
    
    [bValueTable reloadData];
    [self drawGraph:self];
}


-(void) textChanged:(NSNotification *) note
{	
	NSLog(@"Text Changed!");
}

- (ViewerController*) copyFirstViewerWindow:(ViewerController*)currentViewer
{
    // This was taken from copyViewerWindow in ViewerController.m
    
	ViewerController *new2DViewer = nil;
	
	// We will read our current series, and duplicate it by creating a new series!
	
    //for( int v = 0; v < currentViewer.maxMovieIndex; v++)
    for( int v = 0; v < 1; v++)     // Just do 1st frame.
    {
        NSData *vD = nil;
        NSMutableArray *newPixList = nil;
        
        [currentViewer copyVolumeData: &vD andDCMPix:&newPixList forMovieIndex: v];
        
        if( vD)
        {
            // We don't need to duplicate the DicomFile array, because it is identical!
            
            // A 2D Viewer window needs 3 things:
            // A mutable array composed of DCMPix objects
            // A mutable array composed of DicomFile objects
            // Number of DCMPix and DicomFile has to be EQUAL !
            // NSData volumeData contains the images, represented in the DCMPix objects
            if( new2DViewer == nil)
            {
                new2DViewer = [currentViewer newWindow:newPixList :[currentViewer fileList: v] :vD];
                [new2DViewer roiDeleteAll: currentViewer];
            }
            else
                [new2DViewer addMovieSerie:newPixList :[currentViewer fileList: v] :vD];
        }
    }
	
	return new2DViewer;
}

#pragma mark-
#pragma mark Main Diffusion Fits

-(IBAction) calcBiExpMaps:(id)sender     // Initially this is a copy of calcADC.  
                                        // Some consolidation would be good.
// !!! Would be nice to offer "Use IVIM fit for initial guess"
{
	int minbind;                        // Index of minimum b-value
    int cutoffindex=-1;
    
    [self updateThreshold:sender];
	[self updateSynthBValue:sender];
    [self updateInitGuesses:sender];
    nonnegconstraint = ([constraintOn state] == NSOnState);
    showresidual = ([residualOn state] == NSOnState);
    useIVIMinitguess = ([useIVIMguessOn state] == NSOnState);

	
	float nonnegbvalues[MAXNBVALUES];	// Array of non-negative b-values (negative would be ignored)
	int numnonnegbvalues = 0;				// Number of non-negative b-values
	int nonnegindices[MAXNBVALUES];		// Indices of images with non-negative b-values, in order.
	int count1, count2;
	
    // First get number of non-negative B values (eligible for ADC fit)  Sorting is optional here, but easy.
    numnonnegbvalues = sortbvalues(nbvalues, bvals, nonnegindices, nonnegbvalues);

    
	// Check there are >= 3 non-negative B values		
	if (numnonnegbvalues >= 3) {
        
		// Create new 2D viewers.
		ViewerController *newDtViewer = [self copyFirstViewerWindow:self->viewerController];
		ViewerController *newDpViewer = [self copyFirstViewerWindow:self->viewerController];
		ViewerController *newFpViewer = [self copyFirstViewerWindow:self->viewerController];
        ViewerController *newS0Viewer = [self copyFirstViewerWindow:self->viewerController];
        ViewerController *residViewer = [self copyFirstViewerWindow:self->viewerController];
        
		ViewerController *synthViewer;
		
        
		NSMutableArray *synthImage;
		float *synthpix = NULL;
		int count;
		float* bpixels[MAXNBVALUES];	// Pointer to pixels (images) for each b-value, for current slice.
        
		// If synthesizing an image for given B-value, make another viewer.
		if (synthbvalue >= 0) {
			synthViewer = [self copyFirstViewerWindow:self->viewerController];
			synthImage = [synthViewer pixList];
			NSString *synthTitle = [NSString stringWithFormat:@"Synthesized b=%g",synthbvalue];
			[[[synthViewer pixList] objectAtIndex:0] setGeneratedName:synthTitle];
		}
        
        if (nonnegconstraint) {
            [[[newDtViewer pixList] objectAtIndex:0] setGeneratedName:@"Tissue Diffusion (x1e-6mm^2/s)c"];
            [[[newDpViewer pixList] objectAtIndex:0] setGeneratedName:@"Pseudodiffusion (x1e-4mm^2/s)c"];
            [[[newFpViewer pixList] objectAtIndex:0] setGeneratedName:@"Perfusion Fraction (%)c"];
            
        } else {
            [[[newDtViewer pixList] objectAtIndex:0] setGeneratedName:@"Tissue Diffusion (x1e-6mm^2/s)"];
            [[[newDpViewer pixList] objectAtIndex:0] setGeneratedName:@"Pseudodiffusion (x1e-4mm^2/s)"];
            [[[newFpViewer pixList] objectAtIndex:0] setGeneratedName:@"Perfusion Fraction (%)"];
            

        }
		[[[newS0Viewer pixList] objectAtIndex:0] setGeneratedName:@"Fitted Base Signal"];
        [[[residViewer pixList] objectAtIndex:0] setGeneratedName:@"Fit Residual"];
        
		
		// Initialize Wait window
		Wait *splash = [[Wait alloc] initWithString:NSLocalizedString(@"Computing Biexponential Fit", nil)];
		[splash showWindow:self];
		[[splash progress] setMaxValue:zsize];
		[splash setCancel: YES];
		
        // Get pixel value from threshold percentage of max pixel in min-b-value image.
        float thresholdPixVal = [self getThresholdPixValue:numnonnegbvalues
                                               withindices:nonnegindices
                                               withbvalues:nonnegbvalues];

        NSMutableArray *newDtImage = [newDtViewer pixList];			// Get pointer to newly-allocated viewer.
        NSMutableArray *newDpImage = [newDpViewer pixList];			// Get pointer to newly-allocated viewer.
        NSMutableArray *newFpImage = [newFpViewer pixList];			// Get pointer to newly-allocated viewer.
        NSMutableArray *newS0Image = [newS0Viewer pixList];			// Get pointer to newly-allocated viewer.
        NSMutableArray *residImage = [residViewer pixList];			// Get pointer to newly-allocated viewer.
		float *fittedDtPix;
		float *fittedDpPix;
		float *fittedFpPix;
		float *fittedS0Pix;
		float *residPix;
        

        
		// Now calculate the biexponential fit.
		for (count=0; count < zsize; count++) {  // Repeat for each 2D slice in image.
			for (count1=0; count1 < numnonnegbvalues; count1++) {
				// Set pointer for ith non-negative B-value image to pass to calculation.
				bpixels[count1] = [[[viewerController pixList:nonnegindices[count1]] objectAtIndex:count] fImage];
            }
			NSLog(@"%d non-negative b-values",numnonnegbvalues);

            // Get pointers to current slice for each output.
            fittedDtPix = [[newDtImage objectAtIndex:count] fImage];
            fittedDpPix = [[newDpImage objectAtIndex:count] fImage];
            fittedFpPix = [[newFpImage objectAtIndex:count] fImage];
            fittedS0Pix = [[newS0Image objectAtIndex:count] fImage];
            residPix = [[residImage objectAtIndex:count] fImage];
            
            if (useIVIMinitguess) {
                // Set initial estimates from IVIM fit
                
                cutoffindex=-1;                    // Index of first b value over cutoff.
                
                // First get number of non-negative B values and sort.
                numnonnegbvalues = sortbvalues(nbvalues, bvals, nonnegindices, nonnegbvalues);
                
                // Find where the cutoff B value for IVIM is in the list, and make sure there is at least
                // one B=0 image, one image below cutoff, and 2 at/above cutoff.
                count2=1;   // Start at 1, need at least one value for Dp fit.
                while ((count2<numnonnegbvalues-1) && (nonnegbvalues[count2]<ivimCutoff)) {
                    count2++;
                }
                if ((count2<numnonnegbvalues-1) && (nonnegbvalues[0]<1)) {   // Found cutoff, and also B=0 image exists
                    cutoffindex = count2;
                }

                calcIvimFit(bpixels,nxypts, numnonnegbvalues, nonnegbvalues, cutoffindex, thresholdPixVal, fittedDtPix, fittedDpPix, fittedFpPix, fittedS0Pix, NULL, -1, NULL);
                
                // These estimates are put in DICOM-friendly units by above, so need to convert back to physical.
                for (count2=0; count2< nxypts; count2++) {
                    fittedFpPix[count2] /= 100.0;           // Percentage to fraction 0-1
                    fittedDtPix[count2] /= DTCONVERT;
                    fittedDpPix[count2] /= DPCONVERT;
                }
               
            } else {
                // Set initial estimates from UI (note S0Pix is not done this way).
                fittedFpPix[0] = initFp;
                fittedDtPix[0] = initDt;
                fittedDpPix[0] = initDp;
                
                // Set S0 estimate from minimum b-value image.
                minbind = minind(nonnegbvalues, numnonnegbvalues);
                fittedS0Pix[0] = bpixels[minbind][0];  // Get lowest b-val image as init guess
                
            }
            
			if (synthbvalue >= 0) {
				synthpix = [[synthImage objectAtIndex:count] fImage];
			}
			calcBiExpFit(bpixels,nxypts, numnonnegbvalues, nonnegbvalues, thresholdPixVal, fittedDtPix, fittedDpPix, fittedFpPix, fittedS0Pix, residPix, synthbvalue, synthpix,nonnegconstraint,1-useIVIMinitguess);
            
			
			[splash incrementBy: 1];
			//if([splash aborted])
			//	count = zsize;
		}
                
		[newDtViewer refresh];	// Refresh viewer, since pixel values have been replaced 
		[newDpViewer refresh];	// Refresh viewer, since pixel values have been replaced
		[newFpViewer refresh];	// Refresh viewer, since pixel values have been replaced		
        [newS0Viewer refresh];	// Refresh viewer, since pixel values have been replaced
		[residViewer refresh];	// Refresh viewer, since pixel values have been replaced
		
		// Update the current displayed WL & WW (automatic window)
		[[newDtViewer imageView] setWLWW:1000 :2000];
		[[newDpViewer imageView] setWLWW:1000 :2000];
		[[newFpViewer imageView] setWLWW:50 :100];
		
		if (synthbvalue >= 0) {
			[synthViewer refresh];	// Refresh synthesized image viewer.
		} 
		
		[splash close];
		[splash release];
        
		[self closeSheet:sender];
		
		
	} else { // Not enough B-values, so display an error dialog box.
		NSString *msgString = [NSString stringWithFormat:@"(%d found, up to %d expected)",numnonnegbvalues,nbvalues];
		NSRunInformationalAlertPanel(@"Not Enough non-negative B-values (3 required)",msgString,@"Continue", nil, nil);
	}
	
	
}


- (float)getThresholdPixValue:(int)numindices
                withindices:(int *)indices
                  withbvalues:(float *)bvalues
{
    
    int count, count1;
    float *bpixels[MAXNBVALUES];
    float thresholdPixVal=0.0;
    float thresholdThisSlice;
    for (count=0; count < zsize; count++) {  // Repeat for each 2D slice in image.
        for (count1=0; count1 < numindices; count1++) {     // Repeat over all (non-negative) b-values
            // Set pointer for ith non-negative B-value image to pass to calculation.
            bpixels[count1] = [[[viewerController pixList:indices[count1]] objectAtIndex:count] fImage];
        }
        thresholdThisSlice = getThresholdPixValue(bpixels,nxypts,numindices, bvalues, threshold/100);
        NSLog(@"Threshold for slice %d is %g",count+1,thresholdThisSlice);
        
        if (thresholdThisSlice > thresholdPixVal)
            thresholdPixVal = thresholdThisSlice;
    }
    return thresholdPixVal;
}


- (IBAction) calcADC:(id)sender
{
	[self updateThreshold:sender];
	[self updateSynthBValue:sender];
    showresidual = ([residualOn state] == NSOnState);

	float nonnegbvalues[MAXNBVALUES];	// Array of non-negative b-values (negative would be ignored)
	int numnonnegbvalues = 0;				// Number of non-negative b-values
	int nonnegindices[MAXNBVALUES];		// Indices of images with non-negative b-values, in order.
	int count1;

    // First get number of non-negative B values (eligible for ADC fit)  Sorting is optional here, but easy.
    numnonnegbvalues = sortbvalues(nbvalues, bvals, nonnegindices, nonnegbvalues);
		
	// Check there are >= 2 non-negative B values		
	if (numnonnegbvalues >= 2) {
	
		// Create new 2D viewer.
		ViewerController *new2DViewer = [self copyFirstViewerWindow:self->viewerController];
		ViewerController *synthViewer;
		ViewerController *residViewer;
		
		NSMutableArray *adcImage = [new2DViewer pixList];			// Get pointer to newly-allocated viewer.
		float *adcpix;
		NSMutableArray *synthImage;
		float *synthpix = NULL;
		NSMutableArray *residImage;
		float *residpix = NULL;
		int count;
		float* bpixels[MAXNBVALUES];	// Pointer to pixels (images) for each b-value, for current slice.

		// If synthesizing an image for given B-value, make another viewer
		if (synthbvalue >= 0) {
			synthViewer = [self copyFirstViewerWindow:self->viewerController];
			synthImage = [synthViewer pixList];
			NSString *synthTitle = [NSString stringWithFormat:@"Synthesized b=%g",synthbvalue];
			[[[synthViewer pixList] objectAtIndex:0] setGeneratedName:synthTitle];
		}

        // If synthesizing an image for given B-value, make another viewer
		if (showresidual != 0) {
			residViewer = [self copyFirstViewerWindow:self->viewerController];
			residImage = [residViewer pixList];
			NSString *residTitle = [NSString stringWithFormat:@"Residual"];
			[[[residViewer pixList] objectAtIndex:0] setGeneratedName:residTitle];
		}
        
        // ** NONE OF THESE WORK!
    
        //[[new2DViewer window] setTitle:@"ADC Map (x1e-6mm^2/s)"];
        new2DViewer.windowTitle = @"ADC Map (x1e-6mm^2/s)";
        //[[new2DViewer window] setTitle:@"ADC Map (x1e-6mm^2/s)"];
        //[[new2DViewer imageView] checkCursor];
        
		[[[new2DViewer pixList] objectAtIndex:0] setGeneratedName:@"ADC Map (x1e-6mm^2/s)"];
        
		//NSRunInformationalAlertPanel(@"B-value Input:  ",[[bValueList textStorage] string],@"Continue", nil, nil);

		
		// Initialize Wait window
		Wait *splash = [[Wait alloc] initWithString:NSLocalizedString(@"Computing ADC Map", nil)];
		[splash showWindow:self];
		[[splash progress] setMaxValue:zsize];
		[splash setCancel: YES];


        // Get pixel value from threshold percentage of max pixel in min-b-value image.
        float thresholdPixVal = [self getThresholdPixValue:numnonnegbvalues
                                                    withindices:nonnegindices
                                                    withbvalues:nonnegbvalues];
          
		// Now calculate the ADC map.
		for (count=0; count < zsize; count++) {  // Repeat for each 2D slice in image.
			for (count1=0; count1 < numnonnegbvalues; count1++) {
				// Set pointer for ith non-negative B-value image to pass to calculation.
				bpixels[count1] = [[[viewerController pixList:nonnegindices[count1]] objectAtIndex:count] fImage];
							}
			NSLog(@"%d non-negative b-values",numnonnegbvalues);

			adcpix = [[adcImage objectAtIndex:count] fImage];
			if (synthbvalue >= 0) {
				synthpix = [[synthImage objectAtIndex:count] fImage];
			}
			if (showresidual != 0) {
				residpix = [[residImage objectAtIndex:count] fImage];
			}
			calcADCfit(bpixels,nxypts, numnonnegbvalues, nonnegbvalues, adcpix, residpix, thresholdPixVal, NULL, synthbvalue, synthpix);

			
			[splash incrementBy: 1];
			//if([splash aborted])
			//	count = zsize;
		}
				
		[new2DViewer refresh];	// Refresh viewer, since pixel values have been replaced with ADC map.
		
		// Update the current displayed WL & WW (automatic window)
		[[new2DViewer imageView] setWLWW:1000 :2000];
		
		if (synthbvalue >= 0) {
			[synthViewer refresh];	// Refresh synthesized image viewer.
		} 
		
		[splash close];
		[splash release];
	
		[self closeSheet:sender];
		
		
	} else { // Not enough B-values, so display an error dialog box.
		NSString *msgString = [NSString stringWithFormat:@"(%d found, up to %d expected)",numnonnegbvalues,nbvalues];
		NSRunInformationalAlertPanel(@"Not Enough non-negative B-values (2 required)",msgString,@"Continue", nil, nil);
	}
	
	
}


- (IBAction) calcIVIM:(id)sender
{
    [self updateIVIMCutoff:sender];
    [self updateThreshold:sender];
    [self updateSynthBValue:sender];
    showresidual = ([residualOn state] == NSOnState);

    

    float nonnegbvalues[MAXNBVALUES];	// Array of non-negative b-values (negative would be ignored)
    int numnonnegbvalues = 0;				// Number of non-negative b-values
    int nonnegindices[MAXNBVALUES];		// Indices of images with non-negative b-values, in order.
    int count1, count2;
    
    int cutoffindex=-1;                    // Index of first b value over cutoff.

    // First get number of non-negative B values and sort.
    numnonnegbvalues = sortbvalues(nbvalues, bvals, nonnegindices, nonnegbvalues);
 
    // Find where the cutoff B value for IVIM is in the list, and make sure there is at least
    // one B=0 image, one image below cutoff, and 2 at/above cutoff.
    count2=1;   // Start at 1, need at least one value for Dp fit.
    while ((count2<numnonnegbvalues-1) && (nonnegbvalues[count2]<ivimCutoff)) {
        count2++;
    }
    if ((count2<numnonnegbvalues-1) && (nonnegbvalues[0]<1)) {   // Found cutoff, and also B=0 image exists
        cutoffindex = count2;
    }
    
        
    // *** ADD CHECKS HERE:  (1) >=2 B values above cutoff, and (2) a B=0 image
    if (cutoffindex > 0){
        // Create new 2D viewers.
        ViewerController *newDtViewer = [self copyFirstViewerWindow:self->viewerController];
        ViewerController *newDpViewer = [self copyFirstViewerWindow:self->viewerController];
        ViewerController *newFpViewer = [self copyFirstViewerWindow:self->viewerController];
		ViewerController *synthViewer;
        ViewerController *residViewer;
		
        
		NSMutableArray *synthImage;
        NSMutableArray *residImage;
		float *synthpix = NULL;
        float *residpix = NULL;
		int count;
		float* bpixels[MAXNBVALUES];	// Pointer to pixels (images) for each b-value, for current slice.
        
		// If synthesizing an image for given B-value, make another viewer.
		if (synthbvalue >= 0) {
			synthViewer = [self copyFirstViewerWindow:self->viewerController];
			synthImage = [synthViewer pixList];
			NSString *synthTitle = [NSString stringWithFormat:@"Synthesized b=%g",synthbvalue];
			[[[synthViewer pixList] objectAtIndex:0] setGeneratedName:synthTitle];
		}

        // If showing residual, make another viewer
		if (showresidual != 0) {
			residViewer = [self copyFirstViewerWindow:self->viewerController];
			residImage = [residViewer pixList];
			NSString *residTitle = [NSString stringWithFormat:@"IVIM Residual"];
			[[[residViewer pixList] objectAtIndex:0] setGeneratedName:residTitle];
		}
        

        [[[newDtViewer pixList] objectAtIndex:0] setGeneratedName:@"Tissue Diffusion (x1e-6mm^2/s)"];
        [[[newDpViewer pixList] objectAtIndex:0] setGeneratedName:@"Pseudodiffusion (x1e-4mm^2/s)"];
        [[[newFpViewer pixList] objectAtIndex:0] setGeneratedName:@"Perfusion Fraction (%)"];
        
		// Initialize Wait window
		Wait *splash = [[Wait alloc] initWithString:NSLocalizedString(@"Computing Two-Stage IVIM Fit", nil)];
		[splash showWindow:self];
		[[splash progress] setMaxValue:zsize];
		[splash setCancel: YES];
		
        // Get pixel value from threshold percentage of max pixel in min-b-value image.
        float thresholdPixVal = [self getThresholdPixValue:numnonnegbvalues
                                               withindices:nonnegindices
                                               withbvalues:nonnegbvalues];
        
        NSMutableArray *newDtImage = [newDtViewer pixList];			// Get pointer to newly-allocated viewer.
        NSMutableArray *newDpImage = [newDpViewer pixList];			// Get pointer to newly-allocated viewer.
        NSMutableArray *newFpImage = [newFpViewer pixList];			// Get pointer to newly-allocated viewer.
 		float *fittedDtPix;
		float *fittedDpPix;
		float *fittedFpPix;
  
        
		// Now calculate the IVIM maps.
		for (count=0; count < zsize; count++) {  // Repeat for each 2D slice in image.
			for (count1=0; count1 < numnonnegbvalues; count1++) {
				// Set pointer for ith non-negative B-value image to pass to calculation.
				bpixels[count1] = [[[viewerController pixList:nonnegindices[count1]] objectAtIndex:count] fImage];
            }
			NSLog(@"%d b-values",numnonnegbvalues);
            
            fittedDtPix = [[newDtImage objectAtIndex:count] fImage];
            fittedDpPix = [[newDpImage objectAtIndex:count] fImage];
            fittedFpPix = [[newFpImage objectAtIndex:count] fImage];
			if (synthbvalue >= 0) {
				synthpix = [[synthImage objectAtIndex:count] fImage];
			}
			if (showresidual != 0) {
				residpix = [[residImage objectAtIndex:count] fImage];
			}
            
			calcIvimFit(bpixels,nxypts, numnonnegbvalues, nonnegbvalues, cutoffindex, thresholdPixVal, fittedDtPix, fittedDpPix, fittedFpPix, NULL, residpix, synthbvalue, synthpix);
            
			[splash incrementBy: 1];
			//if([splash aborted])
			//	count = zsize;
		}

        
        
		[newDtViewer refresh];	// Refresh viewer, since pixel values have been replaced
		[newDpViewer refresh];	// Refresh viewer, since pixel values have been replaced
		[newFpViewer refresh];	// Refresh viewer, since pixel values have been replaced
		
		// Update the current displayed WL & WW (automatic window)
		[[newDtViewer imageView] setWLWW:1000 :2000];
		[[newDpViewer imageView] setWLWW:1000 :2000];
		[[newFpViewer imageView] setWLWW:50 :100];
		
		if (synthbvalue >= 0) {
			[synthViewer refresh];	// Refresh synthesized image viewer.
		}
		
		[splash close];
		[splash release];
        
		[self closeSheet:sender];

    } else {
        NSString *msgString = [NSString stringWithFormat:@"(%d found, up to %d expected)",numnonnegbvalues,nbvalues];
		NSRunInformationalAlertPanel(@"Need B=0 image, and at least 2 images above cutoff B-value",msgString,@"Continue", nil, nil);

    }
    
}



- (IBAction) endSetupSheet:(id) sender
{
	[self closeSheet:sender];
}

- (void) closeSheet:(id) sender
{
	//NSRunInformationalAlertPanel(@"Closing Sheet:  ",@" ",@"Continue", nil, nil);

	
	[ADCwindow orderOut:sender];
	[NSApp endSheet: ADCwindow returnCode: NSCancelButton];	
	[ADCwindow orderOut:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
}




- (IBAction)drawGraph: (id)sender
{
	int idroi;
    int numTraces=2;    // Ultimately make based on selection;
    int numROIs=0;
	int i;
	int count;
    int count2;
    
    
    float minValueY, maxValueY;
    int minValueX, maxValueX;
    int cutoffindex;
    float sbvalues[MAXNBVALUES];
    int sindices[MAXNBVALUES];
    float svalues[MAXNBVALUES];
    float *svalpointers[MAXNBVALUES];
    int nbvaluesplot;
    float adc, b0fit;
    float thresholdvalue;       // Value to threshold at in fits.
    float maxDataVal;
    float Dp, Dt, Fp, S0, resid;
    NSString *description;
    NSString *residLabel;
    
    maxDataVal=0;
    if ([roiImageList count] >= 1) {
        numROIs = 1;
    }
    // If only showing signal, reduce numTraces
    if ([resultView plotContentType] == 0) {
        numTraces = 1;
    }
    NSLog(@"Number of traces is %d",numTraces);
    
    // B-values may be in arbitrary order, so sort from low to high
    // for plotting, and also remove any negative b-values, which indicate
    // to not include the image/bvalue.
    nbvaluesplot = sortbvalues(nbvalues, bvals, sindices, sbvalues);
    
    // Get options from UI.
    nonnegconstraint = ([constraintOn state] == NSOnState);
    showresidual = ([residualOn state] == NSOnState);
    useIVIMinitguess = ([useIVIMguessOn state] == NSOnState);

    
    NSLog(@"Constraint Flag = %d",nonnegconstraint);

    if (numROIs > 0) {
		// Calculate Mean
		float meanY[nbvalues], stdY[nbvalues], minimumY[nbvalues], maximumY[nbvalues];
		float meanYTotal[nbvalues*numTraces], stdYTotal[nbvalues*numTraces], minimumYTotal[nbvalues*numTraces], maximumYTotal[nbvalues*numTraces];
		
		NSMutableArray *roiNameList  = [[NSMutableArray alloc] init];
		NSMutableArray *roiColorList = [[NSMutableArray alloc] init];
		
		for (idroi = 0; idroi < numROIs; idroi++)
		{
			[self calculateMean:meanY :stdY :minimumY :maximumY :idroi];
			for (i = 0; i <  nbvaluesplot; i++) 
			{
				meanYTotal[idroi*numTraces*nbvaluesplot+i]	 = meanY[sindices[i]];
				stdYTotal[idroi*numTraces*nbvaluesplot+i]	 = stdY[sindices[i]];
				minimumYTotal[idroi*numTraces*nbvaluesplot+i] = minimumY[sindices[i]];
				maximumYTotal[idroi*numTraces*nbvaluesplot+i] = maximumY[sindices[i]];
                svalues[i]=meanY[sindices[i]];  // Keep array of y values for later
                if (svalues[i]>maxDataVal) maxDataVal=svalues[i];
			}
            NSLog(@"Getting ROI information");
			[roiNameList addObject:roiName];        // !!! Need to get this right?
			[roiColorList addObject:roiColor];
			NSLog(@"name of ROI is %@",roiName);
            
            if (numTraces>1) {  // Also showing mono- or bi-exponential fit
                for (i=0; i< nbvaluesplot; i++) 
                    svalpointers[i] = &svalues[i];  // Array of pointers, to be compatible with calcADCfit.
                thresholdvalue = threshold * maxDataVal/100.0;
                [resultView setPlotTitle:@"Signal vs B value"];
                
                if ([resultView plotContentType] == 1) {    // Mono-Exponential
                    
                    if (nbvaluesplot > 1) {
                        
                        for (count=0; count < nbvaluesplot; count++) {
                            NSLog(@"Mono-fit bvalue %d of %d is %g",count,nbvaluesplot,sbvalues[count]);
                        }
                        calcADCfit(svalpointers, 1, nbvaluesplot, sbvalues, &adc, &resid, thresholdvalue, &b0fit, -1, NULL);
                        NSLog(@"MonoExp fit S0=%g, ADC=%g, #bvalues = %d",b0fit,adc,nbvaluesplot);
                        //synthBImage(adc, b0fit, sbvalues, nbvaluesplot, &(meanYTotal[(idroi*numTraces+1)*nbvaluesplot]));
                        synthBiExpImage(adc, 0.0, 0.0, b0fit, sbvalues, nbvaluesplot, &(meanYTotal[(idroi*numTraces+1)*nbvaluesplot]));
                        for (count=0; count < nbvaluesplot; count++) {
                            NSLog(@"Mono-fit bvalue %d of %d is %g.  Sig=%g, PlotSig=%g, Fitted(%d)=%g",count,nbvaluesplot,sbvalues[count],svalpointers[count][0],meanYTotal[count],(idroi*numTraces+1)*nbvaluesplot+count,meanYTotal[(idroi*numTraces+1)*nbvaluesplot+count]);
                        }
                        residLabel = [[NSString alloc] initWithFormat:@", res=%ld",(long)resid ];
                        description = [[NSString alloc] initWithFormat:@"ADC=%.5f, S0=%.0f",adc/DTCONVERT,b0fit];
                    } 
                    else {
                        description = [[NSString  alloc] initWithFormat:@"Not Enough B-Values for Fit"];
                        residLabel = [[NSString alloc] initWithFormat:@"" ];
                        numTraces = 1;
                    }
                }
                else if ([resultView plotContentType] == 2) {   // Two-stage fit
                    
              
                    // Find where the cutoff B value for IVIM is in the list, and make sure there is at least
                    // one B=0 image, one image below cutoff, and 2 at/above cutoff.
                    count2=1;   // Start at 1, need at least one value for Dp fit.
                    while ((count2<nbvaluesplot-1) && (sbvalues[count2]<ivimCutoff)) {
                        count2++;
                    }
            
                    if ((count2<nbvaluesplot-1) && (sbvalues[0]<1)) {   // Found cutoff, and also B=0 image exists
                        cutoffindex = count2;
                    } else cutoffindex = -1;
                    
                    if ((nbvaluesplot > 3) && (cutoffindex > 0)) {
                        
                        calcIvimFit(svalpointers, 1, nbvaluesplot, sbvalues, cutoffindex, thresholdvalue, &Dt, &Dp, &Fp, &S0, &resid, -1, NULL);
                        synthBiExpImage(Dt, Dp, Fp, S0, sbvalues, nbvaluesplot, &(meanYTotal[(idroi*numTraces+1)*nbvaluesplot]));
                        description = [[NSString  alloc] initWithFormat:@"Dt=%.5f*,Dp=%.5f*,Fp=%.0f%%,S0=%.0f",Dt/DTCONVERT,Dp/DPCONVERT,Fp,S0];
                        residLabel = [[NSString alloc] initWithFormat:@", res=%ld",(long)resid ];
                    }
                    
                    else {
                        description = [[NSString  alloc] initWithFormat:@"Need b=0 image and 2+ b-values above cutoff"];
                        residLabel = [[NSString alloc] initWithFormat:@"" ];
                        numTraces = 1;
                    }
                       
                }
                else {  // Bi-Exponential
                    Dt = initDt;
                    Dp = initDp;
                    Fp = initFp;
                    S0 = svalues[0];    // Initial guess as lowest b image.
                    if (nbvaluesplot > 4) {
                        if (useIVIMinitguess) {
                            // !Repeated code from above...!!
                            // Find where the cutoff B value for IVIM is in the list, and make sure there is at least
                            // one B=0 image, one image below cutoff, and 2 at/above cutoff.
                            count2=1;   // Start at 1, need at least one value for Dp fit.
                            while ((count2<nbvaluesplot-1) && (sbvalues[count2]<ivimCutoff)) {
                                count2++;
                            }
                            
                            if ((count2<nbvaluesplot-1) && (sbvalues[0]<1)) {   // Found cutoff, and also B=0 image exists
                                cutoffindex = count2;
                            } else cutoffindex = -1;

                            calcIvimFit(svalpointers, 1, nbvaluesplot, sbvalues, cutoffindex, thresholdvalue, &Dt, &Dp, &Fp, &S0, NULL, -1, NULL);
                            Dt /= DTCONVERT;
                            Dp /= DPCONVERT;
                            Fp /= 100.0;
                            
                            NSLog(@"BiExp IVIM initial guess S0=%g, Dt=%g, Dp=%g, Fp=%g",S0,Dt,Dp,Fp);

                        }
                        calcBiExpFit(svalpointers,1, nbvaluesplot,sbvalues,thresholdvalue, &Dt,&Dp,&Fp,&S0, &resid, -1, NULL, nonnegconstraint,1);
                        NSLog(@"BiExp fit S0=%g, Dt=%g, Dp=%g, Fp=%g",S0,Dt,Dp,Fp);
                        synthBiExpImage(Dt, Dp, Fp, S0, sbvalues, nbvaluesplot, &(meanYTotal[(idroi*numTraces+1)*nbvaluesplot]));
                        if (nonnegconstraint==0) {
                            description = [[NSString  alloc] initWithFormat:@"Dt=%.5f*,Dp=%.5f*,Fp=%.0f%%,S0=%.0f",Dt/DTCONVERT,Dp/DPCONVERT,Fp,S0];
                        } else {
                            description = [[NSString  alloc] initWithFormat:@"Dt=%.5f*,Dp=%.5f*,Fp=%.0f%%,S0=%.0f(bc)",Dt/DTCONVERT,Dp/DPCONVERT,Fp,S0];
                        }
                        residLabel = [[NSString alloc] initWithFormat:@", res=%ld",(long)resid ];

                    } else {
                        numTraces = 1;     // Don't plot trace!
                        description = [[NSString  alloc] initWithFormat:@"Not Enough B-Values for Fit"];
                        residLabel = [[NSString alloc] initWithFormat:@"" ];

                    }

                }

                [roiNameList addObject:@"Fitted"];
                [roiColorList addObject:roiColor];
            }
            else {
                description = [[NSString  alloc] initWithFormat:@"(Signal Only)"];

            }

            
		}
        NSString *plotTitle;
        if (showresidual > 0) {
            plotTitle = [[NSString alloc] initWithFormat:@"%@%@",description,residLabel ];

        } else {
            plotTitle = [[NSString alloc] initWithFormat:@"%@",description ];
            
        }
        [resultView setPlotTitle:plotTitle];
        
        minValueY = 0.0;
        maxValueY = maximumY[0];
        minValueX = 00;
        maxValueX = nbvaluesplot-1;
        //maxValueX = (int)bvals[maxind(bvals,nbvalues)];      // Should really do max check.
        
        NSLog(@"Graph axis limits x=%d,%d, y=%g,%g",minValueX,maxValueX,minValueY,maxValueY);
		
		// Compute minimum and maximum
		//[self computeMin:meanYTotal :numROI*nbvalues :&minTmpNew :nil];
		//[self computeMax:meanYTotal :numROI*nbvalues :&maxTmpNew :nil];
		
		
        // No need to calculate X axis - in Bvals[] already.
        
//		if ([setAutoWindow state] == NSOffState) 
//		{
//			[minYGraphField setEnabled:YES];			[maxYGraphField setEnabled:YES];
//			[minXGraphField setEnabled:YES];			[maxXGraphField setEnabled:YES];//
//		}
//		else  // Use auto window for Y-axis 
//		{  
//			[minYGraphField setFloatValue:minTmp];		[maxYGraphField setFloatValue:maxTmp];
//			[minXGraphField setIntValue:1];				[maxXGraphField setIntValue:ntpts];
//			
//			[minYGraphField setEnabled:NO];				[maxYGraphField setEnabled:NO];
//			[minXGraphField setEnabled:NO];				[maxXGraphField setEnabled:NO];
//		}		
//		minValueY = [minYGraphField floatValue];		maxValueY = [maxYGraphField floatValue];
//		minValueX = [minXGraphField intValue]-1;		maxValueX = [maxXGraphField intValue]-1;
		// NSLog(@"minValueY is %.1f and maxValueY is %.1f",minValueY,maxValueY);
		
        NSLog(@"Calling setParameters");
		[resultView setParameters:nbvaluesplot
								 :meanYTotal 
								 :&minValueY 
								 :&maxValueY 
								 :sbvalues
								 :&minValueX 
								 :&maxValueX 
								 :&numTraces 
								 :roiNameList 
								 :roiColorList 
								 :stdYTotal 
								 :minimumYTotal 
								 :maximumYTotal
								 :[imageView curImage]
								 :[[viewerController pixList] count]];
        NSLog(@"Called setParameters");

	}
	else  // No ROI selected!
	{
		//  Crashing?
        //  [resultView drawBlank];
	}      
    NSLog(@"drawGraph done");
	return;
    
}



// Functions to show information to user about the underlying
// algorithms etc in the plugin.

- (IBAction) showGeneral:(id) sender
{
	NSString *msgString = [NSString stringWithFormat:@"Using images acquired with different B values, this plugin creates ADC map images.  Note the scaling of units to be DICOM compatible.  Use File->Export to Dicom File(s) to store maps in database"];
	NSRunInformationalAlertPanel(@"General Info",msgString,@"Continue", nil, nil);
}

- (IBAction) showCompatibility:(id) sender
{
	NSString *msgString = [NSString stringWithFormat:@"B-values are read from DICOM, but may be entered.  If it does not read B values properly from your DICOM images, please feel free to send me sample DICOM files and we will try to improve it, as different vendors store B values differently in DICOM."];
	NSRunInformationalAlertPanel(@"Compatibility",msgString,@"Continue", nil, nil);
}


- (IBAction) showAlgorithm:(id) sender
{
	NSString *msgString = [NSString stringWithFormat:@"The map is a fit to si=exp(-bi * D) where si are the images at B values bi, and D is the diffusion coefficient.  The fit is a direct fit if 2 B-value-images are given, or a least-squares fit to log(si) vs -(bi * D)"];
	NSRunInformationalAlertPanel(@"Algorithm",msgString,@"Continue", nil, nil);

}


- (IBAction) showCredits:(id)sender
{   
    NSString *msgString = [NSString stringWithFormat:@"Programming:  Brian Hargreaves, Kyung Sung, Deqiang Qiu.  Acknowledgements:  M.I.A. Lourakis (http://wwww.ics.forth.gr/~lourakis/levmar/ )}"];
    NSRunInformationalAlertPanel(@"Algorithm",msgString,@"Continue", nil, nil);
}





#pragma mark-
#pragma mark TableHelperFunctions
// See NSTableView - these are dataSource support functions.

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
// Return number of rows in table, as required for table dataSource.
{
	NSInteger retval = nbvalues;
	return retval;
}


- (id)tableView:(NSTableView *)aTableView 
objectValueForTableColumn:(NSTableColumn *)aTableColumn 
			row:(NSInteger)row;
// Return dataSource information for table - index of image, and b-value.
{
	NSString *msgString;
	if (aTableColumn == [[aTableView tableColumns] objectAtIndex:0]) {
		msgString = [NSString stringWithFormat:@"%ld",row+1];
	} else if (aTableColumn == [[aTableView tableColumns] objectAtIndex:1]) {
		msgString = [NSString stringWithFormat:@"%g",bvals[row]];
		
		// Gray out if bvals[ row] is less than XXX
		if (bvals[ row] < 0) 
			[self setValue:[NSNumber numberWithInt:0] forKey:@"enableButton"];
		else
			[self setValue:[NSNumber numberWithInt:1] forKey:@"enableButton"];
		
		// check if "enableButton" changes
		//NSNumber *n = [self valueForKey:@"enableButton"];
		//NSLog(@"n is %@",n);
		
	} else {
		msgString = [NSString stringWithFormat:@"--"];
	}
	return msgString;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(NSInteger)rowIndex
// Update b-value array with b-value that was changed in table.
{
	bvals[ rowIndex] = [anObject floatValue];	
	
	//NSLog(@"Changed row %u, column = %g",rowIndex+1,[aTableColumn identifier]);
    [self drawGraph: self];	
}

#pragma mark-
#pragma mark C Functions


int minind(float *x, int npts)
// Return the index into the array where the minimum value is found (or 1st if multiple).
{
	int retval=0;
	float minval;
	int count;
	
	minval = *x++;  // Start with minimum value as 1st element value
	
	for (count =1; count < npts; count++)
	{
		if (*x < minval)
		{
			minval=*x;
			retval=count;
		}
		x++;
	}
	return (retval);
}

int maxind(float *x, int npts)
// Return the index into the array where the minimum value is found (or 1st if multiple).
{
	int retval=0;
	float maxval;
	int count;
	
	maxval = *x;
	
	for (count =1; count < npts; count++)
	{
		if (*x > maxval)
		{
			maxval=*x;
			retval=count;
		}
		x++;
	}
	return (retval);
}



void regress(float *x, float *y, int npts, float *m, float *b)
// Do a linear regression of the (x,y) data to find the least squares fit y=mx+b
// If only 2 points are given, the slope/intercept are just calculated to save time.
{
	float sx=0;
	float sy=0;
	float sxx=0;
	float sxy=0;
	int count;
	
	if (npts > 2) {
		for (count=0; count < npts; count++) {
			sx+= *x;
			sy+= *y;
			sxx += (*x) * (*x);
			sxy += (*x++) * (*y++);		
		}
		*m = ((float)npts * sxy - sx*sy) / ((float)npts*sxx - sx*sx);
		*b = (sy - (*m) * sx) / (float)npts;
	} 
	else {									// Return slope/intercept if only 2 data points are given (faster).
		*m = (y[1]-y[0]) / (x[1]-x[0]);
		*b = y[0] - *m * x[0];
	}

	
}

float getThresholdPixValue(float **bpixels, int npts, int nbvalues, float *bvalues, float threshfrac)
// Go through all pixels for image with minimum b-value (of those given) and find the maximum value, then 
// multiply by threshold fraction to return the pixel value to use as a threshold.
{
	int minbindex;
	int maxpixindex;
	float minpixvalue;
	
	minbindex = minind(bvalues,nbvalues);			// Image with minimum B value
	maxpixindex = maxind(bpixels[minbindex],npts);	// Maximum pixel value of this image.
	minpixvalue = bpixels[minbindex][maxpixindex]*threshfrac;		// Threshold pixel value.
	
	return minpixvalue;
}


void synthBiExpImage(float Dt, float Dp, float Fp, float S0, float *bvalues, int nbvalues, float *imvalues)
//  Synthesize bi-exponential fitted values given tissue diffusion, pseudodiffusion, 
//  perfusion fraction and fitted b=0 value (intercept).
//
//  Call with Fp=0, Dp=Don't Care to do monoexponential Sig = S0*exp(-Dt*bvalues).
//
//  (This is just s simple bi-exponential calculation)
//      Dt = Tissue diffusion mm^2/us (DICOM plotting units, ie typically thousands
//      Dp = Tissue diffusion cm^2/us (DICOM plotting units, ie typically thousands
//      Fp = perfusion fraction in percent.
//      S0 = signal fitted at b=0
//      bvalues = b-values in s/mm^2 (ie hundreds to thousands)
//      nbvalues = number of b-values
//      imvalues = output "image" values, in untis of b0fit.
//  Could/should generalize to biexponential fit and use for either.
{
    int count;
    float synthsig;
    
    for (count=0; count < nbvalues; count++) {
        synthsig = S0*((1-Fp/100)* exp(-Dt/DTCONVERT * (*bvalues)) + Fp/100*exp(-Dp/DPCONVERT * (*bvalues)) );
       
        //NSLog(@"Synth image bval %d of %d.  Sig=%g.  Dt=%g,Dp=%g,Fp=%g,S0=%g ",count+1,nbvalues,synthsig,Dt,Dp,Fp,S0);
        
        *imvalues++ = synthsig;
        bvalues++;
    }
}





void calcADCfit(float **bpixels, int npts, int nbvalues, float *bvalues, float *adc, float *resid, float thresh, float *b0fit, float synthbvalue, float *synthim)
// Calculate ADC from b-value images, with regression fit - regress().
//
//	INPUT:
//		bpixels - array of pointers to pixel values for different B-value images
//		npts - number of points per image
//		nbvalues - number of images (each with a B-value)
//		bvalues - B-value for each of the images (arbtirary units, see adc below)
//		thresh - Fraction of maximum pixel value in image with minimum b-value to use as include threshold.
//		synthbvalue - B-value for which to (optionally) synthesize an image once the ADC has been calculated - see synthim.
//		synthim - (also output) if NULL, no image is synthesized.
//
//	OUTPUT:
//		adc - apparent diffusion coefficient, units are inverse of units of bvalues.
//      resid - mean sum-of-squares of residuals.
//		synthim - pointer to output image (allocated) to synthesize.
//      b0fit - pointer to "intercept" or fitted b=0 value.  NULL to just ignore.
// Thresh is the threshold% of maximum in the image with minimum b value for the ADC to be calculated.

{
	int count, count1;
	float synthval;
	float adcval;
    float fitintercept;     //Intercept of fit to -log(Sn) vs Bn, which is really -log(S|B=0)
    float fittedB0;         //exp(fitintercept), Fitted B0 image.
	float *bmin;
	float **bpixptr;
    float diff;
	float logsig[MAXNBVALUES];
    float fittedim[MAXNBVALUES];
	int minbindex;
	int maxpixindex;
	float minpixvalue;				// Minimum pixel value to be used (not thresholded out).
	
	minbindex = minind(bvalues,nbvalues);			// Image with minimum B value
	if (thresh < 1.0) {	// Fraction of max pix passed
				maxpixindex = maxind(bpixels[minbindex],npts);	// Maximum pixel value of this image.
		minpixvalue = bpixels[minbindex][maxpixindex]*thresh;		// Threshold pixel value.
	} else {
		minpixvalue = thresh;	// actual threshold passed.  (Allows same global threshold to be used.)
	}

	
	if (synthbvalue < 0)
	{
		synthim = NULL;		// Don't synthesize image if B value is less than zero.
	}
	
	bmin = bpixels[minbindex];		// Pointer to image for minimum b-value (used to threshold)
	bpixptr = bpixels;
	for (count=0; count < npts; count++) {

		if (*bmin++ > minpixvalue) {
			// Get log(sig) values for fit.
			for (count1=0; count1 < nbvalues; count1++) {
				if (*bpixptr[count1] < 1.0)						// Avoid NaNs
					logsig[count1]=0;
				else
					logsig[count1] = -log(*bpixptr[count1]);		// Get log of pixel value.
							}
			regress(bvalues, logsig, nbvalues, &adcval, &fitintercept);	// Fit ADC value
            
            fittedB0 = exp(-fitintercept);
            if (b0fit != NULL) {
                *b0fit = fittedB0;
            }
            
			// -- Calculate synthetic image if desired
			if (synthim != NULL) {
				synthval = exp(-fitintercept -adcval * synthbvalue);
				if ((synthval < 30000) && (synthval > 0)) {
					*synthim = synthval;
				} else {
					*synthim = 0;
				}
			}
				
            // -- Calculate residual if desired
            if (resid != NULL) {
                synthBiExpImage(adcval*DTCONVERT, 0.0, 0.0, fittedB0, bvalues, nbvalues, fittedim);
                *resid=0.0;
                for (count1=0; count1 < nbvalues; count1++) {
                    
                    diff = (fittedim[count1]-*bpixptr[count1]);
                    *resid += diff*diff;
                   
                    // Print values to debug if xcode.
                    //NSLog(@"Residual Calc value %d of %d.  Fit is %g  Sig=%g, Diff=%g",count1,nbvalues,fittedim[count1],*bpixptr[count1],diff);
                    
                }
                if (nbvalues > 1) {
                    *resid /= (float)(nbvalues);    // Take mean squared difference.
                }
            }
            
			// Check pixels are within DICOM range.
			if ((adcval < 30000) && (adcval > 0))	
				*adc = adcval * DTCONVERT;			// Convert to mm^2/s, convenient for DICOM
			else 
				*adc =0;
		}
		else {					// Pixel is Not above threshold, so set to zero.
            *adc = BELOWTHRESHVALUE;
			         
		}
        // Increment pointers

        adc++;                                              // Increment
        incrementptr(&b0fit);                               // Increments if not null
        for (count1=0; count1 < nbvalues; count1++) {		// Increment pointers to pixels
            (bpixptr[count1])++;
        }
        incrementptr(&resid);                               // Increments if not null
        incrementptr(&synthim);                             // Increments if not null

	}

	
}

void calcIvimFit(float **bpixels,int npts, int nbvalues, float *bvalues, int bcutoffindex, float thresh, float *fitDt, float *fitDp, float *fitFp, float *fitS0, float *resid, float synthbvalue, float *synthim)
// Calculate IVIM parameters from b-value images, with 2-stage monoexponential fit - regress().
//
// Stage 1:  Signals for bvalues >= bcutoffindex are used to calculate tissue diffusion.
//           Perfusion fraction is calculated as signal minus fitted b=0 tissue signal.
// Stage 2:  After subtracting curve from Stage 1, monoexponential fit calculates pseudodiffusion.
//
//  ASSUMPTIONS:  (a) bvalues are monotonically increasing and include b=0, (b) bcutoffindex < nbvalues.
//          !!No error check on this is done here!!
//
//	INPUT:
//		bpixels - array of pointers to pixel values for different B-value images
//		npts - number of points per image
//		nbvalues - number of images (each with a B-value)
//		bvalues - B-value for each of the images (arbtirary units, see adc below)
//      bcutoffindex - Lowest index used for tissue diffusion in fit.
//		thresh - Fraction of maximum pixel value in image with minimum b-value to use as include threshold.
//		synthbvalue - B-value for which to (optionally) synthesize an image once the ADC has been calculated - see synthim.
//		synthim - (also output) if NULL, no image is synthesized.
//
//	OUTPUT:
//		fitDt, fitDp, fitFp - fitted tissue diffusion, pseudodiffusion and perfusion fraction.
//      fitS0 - fitted b=0 signal (if not NULL)
//      resid - sum of squares of residuals
//		synthim - pointer to output image (allocated) to synthesize.
//      b0fit - pointer to "intercept" or fitted b=0 value.  NULL to just ignore.
// Thresh is the threshold% of maximum in the image with minimum b value for the ADC to be calculated.


{
	int count, count1;
	float synthval;
	float tissuediff, pseudodiff, perffrac;
    float fitintercept;     //Intercept of fit to -log(Sn) vs Bn, which is really -log(S|B=0)
    float perfintercept;    //Fitted intercept for perfusion.
	float *bmin;
    float diff;
    float fittedim[MAXNBVALUES];         // Fitted image for residual calculation.
    float fittedS0;         // Fitted S0 signal (temp storage)
	float *bpixptr[MAXNBVALUES];
	float logsig[MAXNBVALUES];
	int minbindex;
	int maxpixindex;
	float minpixvalue;				// Minimum pixel value to be used (not thresholded out).
    int nb0images;
    float sumpix;
    float tissuesignal[MAXNBVALUES];                // Tissue signal (fitted)
    float perfsignal[MAXNBVALUES];                  // Perfusion signal (signal - tissuesignal)

    minbindex = minind(bvalues,nbvalues);			// Image with minimum B value
	if (thresh < 1.0) {	// Fraction of max pix passed
        maxpixindex = maxind(bpixels[minbindex],npts);	// Index of maximum pixel value of this image.
		minpixvalue = bpixels[minbindex][maxpixindex]*thresh;		// Threshold pixel value. 
	} else {
		minpixvalue = thresh;	// actual threshold passed.  (Allows same global threshold to be used.)
	}
    
	
	if (synthbvalue < 0)
		synthim = NULL;		// Don't synthesize image if B value is less than zero.
    
    
    // Figure out how many B=0 images there are, so that we can average the pixel values here.
    for (count=0; count<nbvalues; count++) {
        if (bvalues[count]==0.0) {                //Assume bvalues are sorted and >=0.
            nb0images=count+1;
        }
    }
    
    bmin = bpixels[minbindex];		// Pointer to image for minimum b-value (used to threshold)
    
    for (count1=0; count1 < nbvalues; count1++)
        bpixptr[count1] = bpixels[count1];    // Setup array of pixel pointers to start of each b-val image.

    
    // Do monoexponential fit starting at cutoff value
    
    for (count=0; count<npts; count++) { // Pixel loop
        
		if (*bmin++ > minpixvalue) {  // Thresholding based on pix value in "minimum" b (usually b=0) image.
			//Copy signals from cutoff b onward for fit.
			for (count1=bcutoffindex; count1 < nbvalues; count1++) {
				if (*bpixptr[count1] < 1.0)	{					// Avoid NaNs
					logsig[count1-bcutoffindex]=0;
                } else {
					logsig[count1-bcutoffindex] = -log(*bpixptr[count1]);		// Get log of pixel value.
                }
            }

            
            // Do monoexponential fit to get Tissue Diffusion.
			regress(&(bvalues[bcutoffindex]), logsig, nbvalues-bcutoffindex, &tissuediff, &fitintercept);	// Fit Dt value
 			// Check pixels are within DICOM range.
			if ((tissuediff < 0.03) && (tissuediff > 0)) {
				*fitDt = tissuediff * DTCONVERT;			// Convert to um^2/s, convenient for DICOM
			} else {
				*fitDt=0;
            }
            
            // Calculate fitted curve for Tissue Diffusion
            for (count1=0; count1 < nbvalues; count1++) {
                tissuesignal[count1] = exp(-tissuediff*bvalues[count1]-fitintercept);
                perfsignal[count1] = *(bpixptr[count1]) - tissuesignal[count1];
            }
            
            // Find perfusion fraction from fitted B=0 signal.
            sumpix = 0.0;
            for (count1 = 0; count1 < nb0images; count1++) {  // Loop through all images that have b=0
                sumpix+= *(bpixptr[count1]);
            }
            if (sumpix>0) {
                perffrac = (sumpix-(tissuesignal[0])*nb0images)/sumpix; // Note instead of dividing sumpix twice, multiply S0tissue.
                *fitFp = perffrac*100;
            } else {
                perffrac = 0;
                *fitFp = 0.0;
            }
            
            // Exponential fit for pseudodiffusion/perfusion
			// Get log(sig) values for fit.
			for (count1=0; count1 < nbvalues; count1++) {
				if (perfsignal[count1] < 1.0)						// Avoid NaNs
					logsig[count1]=0;
				else
					logsig[count1] = -log(perfsignal[count1]);		// Get log of pixel value.
                // Debug:  Print values
                if (npts < 2) {
                    NSLog(@"B = %g,  Tissue Sig = %g,  Perfusion Sig = %g,  Log(Perf) = %g",bvalues[count1],tissuesignal[count1],perfsignal[count1],logsig[count1]);
                }
			}
            // Do monoexponential fit to get pseudodiffusion.
			regress(bvalues, logsig, nbvalues, &pseudodiff, &perfintercept);	// Fit Dt value
            
 			// Check pixels are within DICOM range.
			if ((pseudodiff < 3) && (pseudodiff > 0))
				*fitDp = pseudodiff * DPCONVERT;			// Convert to value, convenient for DICOM
			else
				*fitDp=0;
            
            
            // Return base image, if requested, usually mostly for plots.
            if ((fitS0 != NULL) || (resid != NULL)) {
                // NSLog(@"calcIvimFit:  fitted S0 = %g, average of b=0 = %g, num b=0 = %d",exp(-perfintercept)+exp(-fitintercept),sumpix/nb0images,nb0images);
                if (nb0images==0)
                    fittedS0 = exp(-perfintercept) + exp(-fitintercept);
                else
                    fittedS0 = sumpix/nb0images;
                if (fitS0!=NULL) {
                    *fitS0 = fittedS0;      // Just copy value.
                }
            }
            
        
			// -- Calculate synthetic image if desired
			if (synthim != NULL) {
				synthval = exp(-fitintercept -tissuediff * synthbvalue) + exp(-perfintercept - pseudodiff * synthbvalue);
				if ((synthval < 30000) && (synthval > 0)) {
					*synthim = synthval;
				} else {
					*synthim = 0;
				}
			}
            
            // -- Calculate residual if desired
            
            if (resid != NULL) {
                synthBiExpImage(tissuediff*DTCONVERT, pseudodiff*DPCONVERT, perffrac*100,
                                fittedS0, bvalues, nbvalues, fittedim);
                *resid=0.0;
                for (count1=0; count1 < nbvalues; count1++) {
                    
                    diff = (fittedim[count1]-*bpixptr[count1]);
                    *resid += diff*diff;
                    
                    // Print values to debug if xcode.
                    //NSLog(@"IVIM Residual Calc value %d of %d.  Fit is %g  Sig=%g, Diff=%g",count1,nbvalues,fittedim[count1],*bpixptr[count1],diff);
                }
                if (nbvalues > 1) {
                    *resid /= (float)(nbvalues);    // Take mean squared difference.
                }
                
            }
            
		}
		else {					// Pixel is Not above threshold, so set to zero.
            *fitDt = BELOWTHRESHVALUE;
            *fitFp = BELOWTHRESHVALUE;
            *fitDp = BELOWTHRESHVALUE;
            if (synthim != NULL) {
                *synthim = 0.0;
            }
            if (resid != NULL) {
                *resid = 0.0;
            }
    
            
		}
        
        // Increment pointers
        fitDt++;
        fitFp++;
        fitDp++;
        incrementptr(&fitS0);                               // Increment if not null
        for (count1=0; count1 < nbvalues; count1++) {		// Increment pointers to pixels for each b-value image.
				(bpixptr[count1])++;
        }
		incrementptr(&synthim);                             // Increment if not null
		incrementptr(&resid);                               // Increment if not null

    }

    NSLog(@"calcIvimFit:  exp(perfint)=%.6f, exp(diffint)=%.6f  perfint=%g,  diffint=%g",exp(-perfintercept),exp(-fitintercept),perfintercept,fitintercept);
}



void calcBiExpFit(float **bpixels,int npts, int nbvalues, float *bvalues, float thresh, float *fitDt, float *fitDp, float *fitFp, float *fitS0, float *fitresid, float synthbvalue, float *synthim, int uselimitconstraints, int sameguessallpix)
//
// calcBiExpFit - Calculates a biexponential fit S = S0[(1-Fp)exp(-bDt) + Fp*exp(-bDp)]
//
//  Uses levmar.c (Levenberg-Marquardt package for non-linear fitting)
//
//  INPUT:
//      bpixels = pointers to first pixel of image for each b-value
//      npts = number of points per image
//      bvalues = array of b values in s/mm^2
//      thresh = pixel value below which to ignore and not do fit, or if <1, fraction of maximum pixel in min-b-value image
//      [initial guesses passed in output parameters]
//      synthbvalue = b-value for which to synthesize an image after the fit
//      uselimitconstraints = 1 to limit values to be >0 (slower fit).
//      sameguessallpix means initial guess only read from fitDt[0], etc, otherwise read at each pixel.

//  OUTPUT
//      fitDt = fitted tissue diffusion in um^2/s (10^6 mm^2/s) [initial guess passed as input]
//      fitDp = fitted pseudodiffusion in um^/cs (10^4 mm^2/s)  [initial guess passed as input]
//      fitFp = fitted perfustion fraction (%)  [initial guess passed as input]
//      fitS0 = fitted base signal (pixel units)
//      fitresid = fit residual from Levenberg-Marquardt algorithm.
//      synthim = syntesized image at given b-value



{
    
    float *bmin;        // Array of pixels from minimum b-value image passed.
    int minbindex;
    
    float p[4];
    float pinit[4];     // Initial guesses
    float x[MAXNBVALUES];
    float opts[LM_OPTS_SZ], info[LM_INFO_SZ];
    float ubound[4];
    float lbound[4];
    float tempvar;
    
    opts[0]=LM_INIT_MU; opts[1]=1E-15; opts[2]=1E-15; opts[3]=1E-20;
    opts[4]=LM_DIFF_DELTA; // relevant only if the finite difference Jacobian vers
    
    if (sameguessallpix) {
        // Copy initial guesses.
        //pinit[0] = fitS0[0]; // Note for S0, the guess is just the minimum B-value image value.
        pinit[1] = fitFp[0];
        pinit[2] = fitDt[0];
        pinit[3] = fitDp[0];

    }
    
    // -- Bounds (if used)
    lbound[0] = 0.0;    // base-line image value.
    ubound[0] = 1e10;
    lbound[1] = 0.0;    // Perfusion fraction between 0 and 1.
    ubound[1] = 1.0;    
    lbound[2] = 0.0;    // Tissue diffusion non-negative.
    ubound[2] = 1e10;
    lbound[3] = 0.0;    // Pseudo-diffusion non-negative.
    ubound[3] = 1e10;
	
	minbindex = minind(bvalues,nbvalues);			// Image with minimum B value
    bmin = bpixels[minbindex];
    
    int count, bcount;
    for (count=0; count < npts; count++) {          // Loop over all pixels.
        if (*bmin > thresh) {
            // Set parameters to initial guesses
            p[0]=*bmin;                             // Initial guess for S0 is pix val from min-b image.
            if (sameguessallpix) {
                //p[0]=pinit[0];
                p[1]=pinit[1];
                p[2]=pinit[2];
                p[3]=pinit[3];
            } else {            // Get initial guesses from array.
                p[1]=*fitFp;
                p[2]=*fitDt;
                p[3]=*fitDp;
            }
            // Data values
            for (bcount=0; bcount < nbvalues; bcount++) {
                x[bcount] = bpixels[bcount][count];
            }

            if (uselimitconstraints==0) {
                // Do fit for this pixel
                slevmar_der(biexpfunc, jacbiexpfunc, p, x, 4, nbvalues, MAXLEVMARITER, opts, info, NULL, NULL, bvalues); // with analytic Jacobian
            } else {
                // Do box-constrained fit for this pixel
                slevmar_bc_der(biexpfunc, jacbiexpfunc, p, x, 4, nbvalues, lbound, ubound,MAXLEVMARITER, opts, info, NULL, NULL, bvalues); // with analytic Jacobian
            }
            
            // Copy output to arrays.
            if ((p[0] > 30000) || (p[0] < 0)){  
                *fitS0++=0;
            } else { 
                *fitS0++ = p[0];
            }
            // Possibility that fit has pseudo-diffusion lower than tissue diffusion,
            // so in this case flip them.
            if (p[2] > p[3]) {
                p[1] = 1.0-p[1];    // "swap" perfusion fraction.
                tempvar = p[2];     // Swap Dp and Dt...
                p[2] = p[3];
                p[3] = tempvar;
            }
            if ((p[1] > 300) || (p[1] < 0)){        // Perfusion fraction, scale to percent
                *fitFp++=0;
            } else { 
                *fitFp++ = p[1]*100;
            }

            if ((p[2] > 0.03) || (p[2] < 0)){       // Tissue Diffusion, limit to 0.03 mm^2/s, scale to um^2/s
                *fitDt++=0;
            } else { 
                *fitDt++ = p[2]*DTCONVERT;
            }
            
            if (p[3] > 3) {                         // Pseudo-diffusion, limit to 3 um^2/s, scale to 100um^2/us
                *fitDp++=30000;
            } else if (p[3] < 0){  
                *fitDp++=0;
            } else { 
                *fitDp++ = p[3]*DPCONVERT;
            }

            *fitresid++ = info[1];
            
            if (synthim != NULL) {                      // Synthesize image.
                biexpfunc(p,x,4,3,&synthbvalue);
                if ((x[0] < 30000) && (x[0] > 0)) {
                    *synthim++ = x[0];
                } else {
                    *synthim++ = 0;
                }
            }
            
        } else {                        // Pixel below threshold - set all outputs to zero.
            *fitS0++ = BELOWTHRESHVALUE;
            *fitFp++ = BELOWTHRESHVALUE;
            *fitDt++ = BELOWTHRESHVALUE;
            *fitDp++ = BELOWTHRESHVALUE;
            *fitresid++=BELOWTHRESHVALUE;
            
            if (synthbvalue > 0) {
                *synthim++=0;
            }
        }
        bmin++;                         // Increment pixel pointer for min-b-value image.
    }
    
    
}



int sortbvalues(int nbvalues, float *bvalues, int *sortedindices, float *sortedbvalues) {
    // Sort non-negative bvalues, and place negative indices at top.
    // Return array of indices into bvalues[] and ordered array.
    // Return number that are greater than or equal to zero.
    int i,j;
    float tempb, maxb;
    int tempi;
    int numnegative=0;

    // First copy values and make array of indices
    for (i=0; i<nbvalues; i++) {
        sortedindices[i]=i;
        sortedbvalues[i]=bvalues[i];
        if (bvalues[i] > maxb) maxb=bvalues[i];
    }
    // For negative b, set them to over maximum so sort will work.
    for (i=0; i<nbvalues; i++) {
        if (sortedbvalues[i] < 0) {
            sortedbvalues[i] = maxb+1;
            numnegative++;
        }        
        
    }
    
    // Now bubble-sort array:
    for (i=0; i<nbvalues-1; i++) {
        for (j=nbvalues-2; j>=0; j--) {
            if (sortedbvalues[j+1] < sortedbvalues[j]) {
                tempb = sortedbvalues[j];
                sortedbvalues[j]=sortedbvalues[j+1];
                sortedbvalues[j+1]=tempb;
                tempi = sortedindices[j];
                sortedindices[j]=sortedindices[j+1];
                sortedindices[j+1]=tempi;
            }
        }
    }
    return nbvalues-numnegative;
}

#pragma mark-
#pragma mark Math Functions


- (void) calculateMean: (float *) meanY :(float *) stdY :(float *) minimumY :(float *) maximumY :(int) indexROI
{
	NSLog(@"calculateMean!");
	float rmean, rtotal, rdev, rmin, rmax;
	int i;
    
	for (i = 0; i < nbvalues; i++) 
	{
		// If #ROIs are smaller than indexROI, use the one at the first time point
		// if (roiImageList.count < *indexROI+1)
		//		roiImageList = [[viewerController roiList] objectAtIndex: [imageView curImage]];
		
		// When ROIs exist!
		if (roiImageList.count != 0) 
		{
			curROI = [roiImageList objectAtIndex:indexROI]; // 0 is a selected ROI
			
			DCMPix *curPix = [[viewerController pixList:i] objectAtIndex:[imageView curImage]];
			[curPix computeROI: curROI :&rmean :&rtotal :&rdev :&rmin :&rmax];
			//NSLog(@"ROI exists");
			*meanY++ = rmean;
			*stdY++ = rdev;
			*minimumY++ = rmin;
			*maximumY++ = rmax;
			
            NSLog(@"calculateMean:  b=%g, val=%g",bvals[i],rmean);
            
			if (i == 0) // get ROI name and color from the first time point
			{
				// Find the current ROI name
				roiName = [curROI name];
				// Find the current ROI color
				roiColor = [curROI NSColor];
			}
		}
	}
	NSLog(@"CalculateMean Done");
}

void incrementptr(float **ptr)
// Increments the value of *ptr if not null.
{
    if (*ptr != NULL) {
        (*ptr)++;
    }
}

@end
