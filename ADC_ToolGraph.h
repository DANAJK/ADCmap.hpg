//
//  ADC_ToolGraph.h
//  ADCMap
//
//  Created by Kyung Sung on 2/28/10.
//  Copyright 2010 Stanford University. All rights reserved.
//  Modified by Brian Hargreaves


#import <Cocoa/Cocoa.h>

@interface ADC_ToolGraph : NSView {
	long nnTimeHere;
	int i, idroi, minValueX, maxValueX, numValueROI, flag_blank, minPoint, maxPoint, selectedRegion, maxZZ, curZZ;
	float meanHere[100][100], stdYHere[100][100], minimumYHere[100][100], maximumYHere[100][100], minValueY, maxValueY, timeXHere[100], yAxisLoc[100], yAxisValue[100], xAxisLoc[100], xAxisTime[100];
	NSBezierPath *path;
	NSMutableArray *roiNameListHere, *roiColorListHere;
	NSColor			*bgColor, *txtColor;
    NSString    *plotTitle;

	IBOutlet NSButton		*gridOn;
	IBOutlet NSButton		*legendOn;
	
	IBOutlet NSMatrix		*legendName;
	IBOutlet NSPopUpButton	*typeSignal2;
}

- (void) setParameters: (long) nnTime :(float *) meanY :(float *) minY :(float *) maxY :(float *) timeX :(int *) minX :(int *) maxX :(int *) numROI :(NSMutableArray *) roiNameList :(NSMutableArray *) roiColorList :(float *) stdY :(float *) minimumY :(float *) maximumY :(int)curSlice :(int)maxSlice;
- (void) drawXAxis:(float *) timeX :(int) minX :(int) maxX :(int) numXaxis :(int) stepTime :(NSRect) r;
- (void) drawYAxis:(float) minY :(float) maxY :(int) numYaxis :(int) stepValue :(NSRect) r; 
- (void) drawSelectedRegion:(NSRect) r;
- (void) drawXGrid:(NSRect) r;
- (void) drawYGrid:(int) numYaxis :(NSRect) r;
- (void) drawLegend:(NSRect) r;
- (void) drawPlot:(NSRect) r;
- (void) nameAxes;
- (void) drawBlank;
- (void) makeSelectedRegion:(int) minP :(int) maxP;

- (void) dicomSave:(NSString*)seriesDescription backgroundColor:(NSColor*)backgroundColor toFile:(NSString*)filename;
- (void) savePDF;
- (void) saveTXT;
- (void) didPDFEnd:(NSSavePanel *)sheet returnCode:(int)code contextInfo:(void *)contextInfo;
- (void) didTXTEnd:(NSSavePanel *)sheet returnCode:(int)code contextInfo:(void *)contextInfo;
- (int) plotContentType;
- (void) setPlotTitle:(NSString *)title;

@end


