//
//  biexpfit.h
//  ADCmap
//
//  Created by Brian Hargreaves on 10/18/11.
//  Copyright (c) 2011 Stanford University. All rights reserved.
//

#ifndef ADCmap_biexpfit_h
#define ADCmap_biexpfit_h

/* Structure to pass data through levmar program. */
struct {
    int nbvalues;
    float *bvalues;
} biexp_data;

/* Functions used to perform levmar minimization */

void biexpfunc(float *p, float *x, int m, int n, void *data);

void jacbiexpfunc(float *p, float *jac, int m, int n, void *data);

#endif
