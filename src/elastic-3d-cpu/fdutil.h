#ifndef _fdutil_h
#define _fdutil_h


typedef struct fdm2 *fdm2d;


typedef struct fdm3 *fdm3d;


typedef struct scoef2 *scoef2d;


typedef struct scoef3 *scoef3d;


typedef struct lcoef2 *lint2d;


typedef struct lcoef3 *lint3d;


typedef struct abc2 *abcone2d;


typedef struct abc3 *abcone3d;


typedef struct spon *sponge;


typedef struct ofg *ofg2d;


typedef struct PML2D *PML2D;


typedef struct PML3D *PML3D;


struct fdm2{
    int nb;
    int   nz,nzpad;
    int   nx,nxpad;
    float oz,ozpad;
    float ox,oxpad;
    float dz;
    float dx;
    bool verb;
    bool free;
    int ompchunk;
};


struct fdm3{
    int nb;
    int   nz,nzpad;
    int   nx,nxpad;
    int   ny,nypad;
    float oz,ozpad;
    float ox,oxpad;
    float oy,oypad;
    float dz;
    float dx;
    float dy;
    bool verb;
    bool free;
    int ompchunk;
};


struct scoef2{
    int n;
    int ix,iz;
    int fx,fz,nx,nz;
    float sincx[9], sincz[9];
};


struct scoef3{
    int n;
    int iy,ix,iz;
    int fy,fx,fz,ny,nx,nz;
    float sincy[9],sincx[9], sincz[9];
};


struct lcoef2{
    int n;
    float *w00;
    float *w01;
    float *w10;
    float *w11;
    int *jz;
    int *jx;
};


struct lcoef3{
    int n;
    float *w000;
    float *w001;
    float *w010;
    float *w011;
    float *w100;
    float *w101;
    float *w110;
    float *w111;
    int *jz;
    int *jx;
    int *jy;
};


struct abc2{
    bool free;
    float *bzl;
    float *bzh;
    float *bxl;
    float *bxh;
};


struct abc3{
    bool free;
    float**bzl;
    float**bzh;
    float**bxl;
    float**bxh;
    float**byl;
    float**byh;
};


struct spon{
    float *w;
};


struct ofg{
    float **tt;
};


struct PML2D{
    float **up;
    float **down;
    float **right;
    float **left;
    float **upright;
    float **downright;
    float **downleft;
    float **upleft;
};


struct PML3D{
    float ***Upsizx; float ***Upsizy; float ***UPSIzxy;
    float ***Dpsizx; float ***Dpsizy; float ***DPSIzxy;
    float ***Fpsiyx; float ***Fpsiyz; float ***FPSIyzx;
    float ***Bpsiyx; float ***Bpsiyz; float ***BPSIyzx;
    float ***Lpsixy; float ***Lpsixz; float ***LPSIxyz;
    float ***Rpsixy; float ***Rpsixz; float ***RPSIxyz;
    float ***ULPSIzxy; float ***URPSIzxy;
    float ***DLPSIzxy; float ***DRPSIzxy;
    float ***UFPSIyzx; float ***UBPSIyzx;
    float ***DFPSIyzx; float ***DBPSIyzx;
    float ***LFPSIxyz; float ***RFPSIxyz;
    float ***LBPSIxyz; float ***RBPSIxyz;
    float ***ULU; float ***URU; float ***DRU; float ***DLU;
    float ***UFU; float ***UBU; float ***DBU; float ***DFU;
    float ***LFU; float ***RFU; float ***RBU; float ***LBU;
    float ***ULFW;   float ***URFW;   float ***DRFW;   float ***DLFW;
    float ***ULBW;   float ***URBW;   float ***DRBW;   float ***DLBW;
};


/*------------------------------------------------------------*/
fdm2d fdutil_init(bool verb_,
		  bool free_,
		  sf_axis az_,
		  sf_axis ax_,
		  int     nb_,
		  int ompchunk_);
/*< init fdm utilities >*/


/*------------------------------------------------------------*/
fdm3d fdutil3d_init(bool verb_,
		    bool free_,
		    sf_axis az_,
		    sf_axis ax_,
		    sf_axis ay_,
		    int     nb_,
		    int ompchunk_);
/*< init fdm utilities >*/


/*------------------------------------------------------------*/
ofg2d offgrid_init(fdm2d fdm);
/*< init off-grid interpolation >*/


/*------------------------------------------------------------*/
void offgridfor(float **ti,
		ofg2d  ofg,
		fdm2d  fdm);
/*< forward off-grid interpolation (in place) >*/


/*------------------------------------------------------------*/
void offgridadj(float **ti,
		ofg2d  ofg,
		fdm2d  fdm);
/*< adjoint off-grid interpolation (in place) >*/


/*------------------------------------------------------------*/
void expand(float** a,
	    float** b,
	    fdm2d fdm);
/*< expand domain >*/


/*------------------------------------------------------------*/
void wpad2d(float **out,
	    float **inp,
	    fdm2d   fdm);
/*< pad wavefield >*/


void wpad3d(float ***out,
	    float ***inp,
	    fdm3d    fdm);
/*< pad wavefield >*/


void wwin2d(float **out,
	    float **inp,
	    fdm2d   fdm);
/*< win wavefield >*/


void wwin3d(float ***out,
	    float ***inp,
	    fdm3d    fdm);
/*< win wavefield >*/


/*------------------------------------------------------------*/
void expand3d(float ***a,
	      float ***b,
	      fdm3d  fdm);
/*< expand domain >*/


/*------------------------------------------------------------*/
void cut2d(float**  a,
	   float**  b,
	   fdm2d  fdm,
	   sf_axis cz,
	   sf_axis cx);
/*< cut a rectangular wavefield subset >*/


/*------------------------------------------------------------*/
void cut3d(float*** a,
	   float*** b,
	   fdm3d  fdm,
	   sf_axis cz,
	   sf_axis cx,
	   sf_axis cy);
/*< cut a rectangular wavefield subset >*/


/*------------------------------------------------------------*/
void cut3d_slice(float** a,
                 float** b,
                 fdm3d  fdm,
                 sf_axis cz,
                 sf_axis cx);
/*< cut a rectangular wavefield subset >*/


/*------------------------------------------------------------*/
void bfill(float** b,
	   fdm2d fdm);
/*< fill boundaries >*/


/*------------------------------------------------------------*/
scoef3d sinc3d_make(int nc,
		    pt3d* aa,
		    fdm3d fdm);
/*< init the sinc3d interpolation for injection/extraction >*/


/*------------------------------------------------------------*/
void sinc3d_inject(float***uu,
		   float *dd,
		   scoef3d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void sinc3d_inject1(float***uu,
		    float dd,
		    scoef3d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void sinc3d_extract(float***uu,
		    float *dd,
		    scoef3d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void sinc3d_extract1(float***uu,
		     float *dd,
		     scoef3d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
scoef2d sinc2d_make(int nc,
		    pt2d* aa,
		    fdm2d fdm);
/*< init the sinc2d interpolation for injection/extraction >*/


/*------------------------------------------------------------*/
void sinc2d_inject(float**uu,
		   float *dd,
		   scoef2d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void sinc2d_inject1(float**uu,
		    float dd,
		    scoef2d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void sinc2d_extract(float**uu,
                    float *dd,
                    scoef2d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void sinc2d_extract1(float**uu,
		     float *dd,
		     scoef2d ca);
/*< extract from wavefield >*/


/*------------------------------------------------------------*/
lint2d lint2d_make(int    na,
		   pt2d*  aa,
		   fdm2d fdm);
/*< init 2D linear interpolation >*/


/*------------------------------------------------------------*/
lint3d lint3d_make(int    na,
		   pt3d*  aa,
		   fdm3d fdm);
/*< init 3D linear interpolation >*/


/*------------------------------------------------------------*/
void lint2d_hold(float**uu,
		 float *ww,
		 lint2d ca);
/*< hold fixed value in field >*/


/*------------------------------------------------------------*/
void lint2d_inject(float**uu,
		   float *dd,
		   lint2d ca);
/*< inject into wavefield >*/


void lint2d_extract(float**uu,
		    float* dd,
		    lint2d ca);
/*< extract from wavefield >*/


/*------------------------------------------------------------*/
void lint3d_inject(float***uu,
		   float  *dd,
		   lint3d  ca);
/*< inject into wavefield >*/


void lint3d_extract(float***uu,
		    float  *dd,
		    lint3d  ca);
/*< extract from wavefield >*/


/*------------------------------------------------------------*/
void lint2d_inject1(float**uu,
		    float  dd,
		    lint2d ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void lint3d_inject1(float***uu,
		    float   dd,
		    lint3d  ca);
/*< inject into wavefield >*/


/*------------------------------------------------------------*/
void fdbell_init(int n);
/*< init bell taper >*/


/*------------------------------------------------------------*/
void fdbell3d_init(int n);
/*< init bell taper >*/


/*------------------------------------------------------------*/
void lint2d_bell(float**uu,
		 float *ww,
		 lint2d ca);
/*< apply bell taper >*/


/*------------------------------------------------------------*/
void lint3d_bell(float***uu,
		 float  *ww,
		 lint3d  ca);
/*< apply bell taper >*/


/*------------------------------------------------------------*/
void lint2d_bell1(float**uu,
		  float ww,
		  lint2d ca);
/*< apply bell taper >*/


/*------------------------------------------------------------*/
void lint3d_bell1(float***uu,
		  float  ww,
		  lint3d  ca);
/*< apply bell taper >*/


/*------------------------------------------------------------*/
abcone2d abcone2d_make(int     nop,
		       float    dt,
		       float**  vv,
		       bool   free,
		       fdm2d   fdm);
/*< init 2D ABC >*/


/*------------------------------------------------------------*/
abcone3d abcone3d_make(int     nop,
		       float    dt,
		       float ***vv,
		       bool   free,
		       fdm3d   fdm);
/*< init 3D ABC >*/


/*------------------------------------------------------------*/
void abcone2d_apply(float**   uo,
		    float**   um,
		    int      nop,
		    abcone2d abc,
		    fdm2d    fdm);
/*< apply 2D ABC >*/


/*------------------------------------------------------------*/
void abcone3d_apply(float  ***uo,
		    float  ***um,
		    int      nop,
		    abcone3d abc,
		    fdm3d    fdm);
/*< apply 3D ABC >*/


/*------------------------------------------------------------*/
sponge sponge_make(int nb);
/*< init boundary sponge >*/


/*------------------------------------------------------------*/
void sponge2d_apply(float**   uu,
		    sponge   spo,
		    fdm2d    fdm);
/*< apply boundary sponge >*/


/*------------------------------------------------------------*/
void sponge3d_apply(float  ***uu,
		    sponge   spo,
		    fdm3d    fdm);
/*< apply boundary sponge >*/


bool cfl_generic(
    float vpmin, float vpmax,
    float dx, float dy, float dz,
    float dt, float fmax, float safety,
    int intervals, char *wave);
/*< cfl check for both 2d and 3d acoustic fdcode >*/


bool cfl_elastic(
    float vpmin, float vpmax,
    float vsmin, float vsmax,
    float dx, float dy, float dz,
    float dt, float fmax, float safety,
    int intervals);
/*< cfl check for both 2d and 3d elastic fdcode >*/


bool cfl_acoustic(
    float vpmin, float vpmax,
    float dx, float dy, float dz,
    float dt, float fmax, float safety,
    int intervals);
/*< cfl check for acoustic wave equation >*/


/****************/
/* PML ROUTINES */
/****************/
/*------------------------------------------------------------*/
PML2D pml2d_init(fdm2d fdm);
/*< initialize the 2D PML >*/


/*------------------------------------------------------------*/
PML3D pml3d_init(fdm3d fdm);
/*< initialize the 3D PML >*/


/*------------------------------------------------------------*/
void pml2d_velApply(float **vz,
                    float **vx,
                    float dt,
                    float *sigma,
                    fdm2d fdm);
/*< Application of the 2D PML to the velocity field >*/


/*------------------------------------------------------------*/
void pml3d_velApply(float ***vx,
                    float ***vy,
                    float ***vz,
                    float dt,
                    float *sigma,
                    fdm3d fdm);
/*< Application of the 3D PML to the velocity field >*/


/*------------------------------------------------------------*/
void pml2d_presApply(float   **u,
                     float  **vx,
                     float  **vz,
                     float    dt,
                     PML2D   pml,
                     float **com,
                     float *sigma,
                     fdm2d   fdm);
/*< Application of the 2D PML to the pressure field >*/


/*------------------------------------------------------------*/
void pml3d_presApply(float   ***u,
                     float  ***vx,
                     float  ***vy,
                     float  ***vz,
                     float     dt,
                     PML3D    pml,
                     float ***com,
                     float *sigma,
                     fdm3d    fdm);
/*< Application of the 3D PML to the pressure field >*/


/*------------------------------------------------------------*/
void pml2d_free(PML2D pml);
/*< free the memory allocated for the 2D PML >*/


/*------------------------------------------------------------*/
void pml3d_free(PML3D pml);
/*< free the memory allocated for the 3D PML >*/

#endif