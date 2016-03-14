//
//  ADCmapFilter.h
//  ADCmap
//
//  Copyright (c) 2010 Brian. All rights reserved.
//
//



#import <Foundation/Foundation.h>
#import "PluginFilter.h"
#import "DCMObject.h"
#import "DCMAttributeTag.h"
#import "ADC_ToolGraph.h"


#include <math.h>
#include "levmar.h"
#include "biexpfit.h"

#define MAXNBVALUES		100		// A bit arbitrary...
#define MAXLEVMARITER   200     // Max Iterations of LevMar...
#define BELOWTHRESHVALUE 0.0    // Value to assign in fits if pixel below threshold (0/0 = NaN)
#define DTCONVERT  1000000      // Convert from mm^2/s to um^2/s (better for DICOM)
#define DPCONVERT  10000        // Convert from mm^2/s to um^2/cs (better for DICOM)

@interface ADCmapFilter : PluginFilter {

	IBOutlet NSWindow *ADCwindow;
	IBOutlet NSTextField *thresholdField;
	IBOutlet NSTableView *bValueTable;
	IBOutlet NSTextField *synthBField;

    IBOutlet NSButton		*constraintOn;
    IBOutlet NSButton       *residualOn;
    IBOutlet NSButton       *useIVIMguessOn;  // Use IVIM fit for initial guess.
    IBOutlet ADC_ToolGraph *resultView;
    IBOutlet NSTextField *initFpField;      // Text field for initial Fp //
    IBOutlet NSTextField *initDtField;      // Text field for initial Dt //
    IBOutlet NSTextField *initDpField;      // Text field for initial Dp //
    
    IBOutlet NSTextField *ivimCutoffField;

	NSWindowController *window;
	
	// Image Sizes (get/calculate for convenience)
	long nxypts;
	long zsize;		// #pixels (slices) in Z
	
	int nbvalues;
	
    int nonnegconstraint;       // Constrain bi-exp fit values to be positive if set.
    
	float bvals[MAXNBVALUES];	// B values in s^2/mm
	float threshold;			// % of maximum pixel (in min-b image) to use.
	float synthbvalue;			// B value at which to synthesize an image 
	int showresidual;           // Show residual (mean R^2) in fits (parameter or image)
    int useIVIMinitguess;       // Use IVIM fit for initial guess for biexponential fit.
    float initFp;               // Initial guess for Fp (perfusion fraction)
    float initDt;               // Initial guess for Dt (tissue diffusion)
    float initDp;               // Initial guess for Dp (perfusion pseudodiffusion)
    
    float ivimCutoff;           // Cutoff for 2-stage IVIM fit.
    
    NSMutableArray  *roiImageList;  
	NSMutableArray  *viewersNameList;
	NSArray			*keys;
	NSArray			*sortedKeys;
	NSString		*roiName;
	NSColor			*roiColor;
	NSString		*sopuid;
    
	ROI				*curROI;
    DCMView         *imageView;
    
	BOOL enableButton;
}

- (long) filterImage:(NSString*) menuName;

- (void) awakeFromNib;
- (void)roiChanged:(NSNotification *) note;

- (IBAction) endSetupSheet:(id) sender;

- (float)getThresholdPixValue:(int)numindices
                  withindices:(int *)indices
                  withbvalues:(float *)bvalues;

- (IBAction) calcADC:(id)sender;
- (IBAction) calcBiExpMaps:(id)sender;
- (IBAction) calcIVIM:(id)sender;


- (void) textChanged:(NSNotification *) note;
- (void) getBValues;	// Get B Values from DICOM header.

- (void) closeSheet:(id) sender;

- (IBAction) showGeneral:(id) sender;
- (IBAction) showCompatibility:(id) sender;
- (IBAction) showAlgorithm:(id) sender;
- (IBAction) updateThreshold:(id) sender;
- (IBAction) updateSynthBValue:(id) sender;
- (IBAction) updateInitGuesses:(id)sender;
- (IBAction) negateBvalues:(id)sender;
- (IBAction) negateSelBvalues:(id)sender;
- (IBAction)updateIVIMCutoff:(id)sender;


// Table Helper methods
//- (void)tableView:(NSTableView *)aTableView
//   setObjectValue:(id)anObject
//  forTableColumn:(NSTableColumn *)aTableColumn
//			  row:(int)rowIndex;

//- (int)numberOfRowsInTableView:(NSTableView *)aTableView;

//- (id)tableView:(NSTableView *)aTableView
//	objectValueForTableColumn:(NSTableColumn *)aTableColumn
//		   row:(int)row;
- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(NSInteger)rowIndex;

- (IBAction) drawGraph:(id) sender;
- (void) calculateMean: (float *) meanY :(float *) stdY :(float *) minimumY :(float *) maximumY :(int) indexROI;

// C Functions

int minind(float *x, int npts);
int maxind(float *x, int npts);

void regress(float *x, float *y, int npts, float *m, float *b);
float getThresholdPixValue(float **bpixels, int npts, int nbvalues, float *bvalues, float threshfrac);
void synthBiExpImage(float Dt, float Dp, float Fp, float S0, float *bvalues, int nbvalues, float *imvalues);

void calcADC(float *b0, float *bN, int npts, float bvalue, float *adc);
void calcADCfit(float **bpixels, int npts, int nbvalues, float *bvalues, float *adc, float *resid, float thresh, float *b0fit, float synthbvalue, float *synthim);
void calcIvimFit(float **bpixels,int npts, int nbvalues, float *bvalues, int bcutoffindex, float thresh, float *fitDt, float *fitDp, float *fitFp, float *fitS0, float *resid, float synthbvalue, float *synthim);

void calcBiExpFit(float **bpixels,int npts, int nbvalues, float *bvalues, float thresh, float *fitDt, float *fitDp, float *fitFp, float *fitS0, float *fitresid, float synthbvalue, float *synthim, int nonnegconstraints, int sameguessallpix);
int sortbvalues(int nbvalues, float *bvalues, int *sortedindices, float *sortedbvalues);

void incrementptr(float **ptr);

@end
