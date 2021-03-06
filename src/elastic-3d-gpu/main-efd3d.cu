
extern "C" {
#include <rsf.h>
#include "fdutil.h"
#include "vel.h"
#include "box.h"
#include "check.h"
#include "interpfunc.h"
}

#include <cuda.h>
#include <sys/time.h>
#include <assert.h>
#include "ewefd3d_kernels.h"

#define MIN(x, y) (((x) < (y)) ? (x) : (y))
#define NOP 4 /* derivative operator half-size */

bool checksame(const fdm3d &a, const fdm3d &b) {
 return a->nzpad == b->nzpad && a->nxpad == b->nxpad &&  a->nypad == b->nypad &&
        a->oz == b->oz &&  a->ox == b->ox &&  a->oy == b->oy &&
        a->dz == b->dz &&  a->dx == b->dx &&  a->dy == b->dy;
}


static void interp_host_den_vel_patch_n(const fdm3d &oldfdm, const fdm3d &newfdm, const fdm3d &fullfdm, const float *sinc_table, int ntab, int lsinc, float ***full_h_ro, float ***full_h_c11, float ***full_h_c22, float ***full_h_c33, float ***full_h_c44, float ***full_h_c55, float ***full_h_c66, float ***full_h_c12, float ***full_h_c13, float ***full_h_c23, float ***full_h_vp, float ***full_h_vs, float ***&h_ro, float ***&h_c11, float ***&h_c22, float ***&h_c33, float ***&h_c44, float ***&h_c55, float ***&h_c66, float ***&h_c12, float ***&h_c13, float ***&h_c23, float ***&h_vp, float ***&h_vs)
{
  if (checksame(oldfdm, newfdm)) {
    sf_warning("old and new dimensions for den/vel are the same, don't need interpolatin");
    return;
  }

  struct timeval start, stop;
  gettimeofday(&start, NULL);

  free(**h_ro); free(*h_ro); free(h_ro); h_ro = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c11); free(*h_c11); free(h_c11); h_c11 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c22); free(*h_c22); free(h_c22); h_c22 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c33); free(*h_c33); free(h_c33); h_c33 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c44); free(*h_c44); free(h_c44); h_c44 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c55); free(*h_c55); free(h_c55); h_c55 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c66); free(*h_c66); free(h_c66); h_c66 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c12); free(*h_c12); free(h_c12); h_c12 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c13); free(*h_c13); free(h_c13); h_c13 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_c23); free(*h_c23); free(h_c23); h_c23 = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_vp); free(*h_vp); free(h_vp); h_vp = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  free(**h_vs); free(*h_vs); free(h_vs); h_vs = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);

  int narray = 12;
  float *input[] = {full_h_ro[0][0], full_h_c11[0][0], full_h_c22[0][0], full_h_c33[0][0], full_h_c44[0][0], full_h_c55[0][0], full_h_c66[0][0], full_h_c12[0][0], full_h_c13[0][0], full_h_c23[0][0], full_h_vp[0][0], full_h_vs[0][0]};
  float *output[] = {h_ro[0][0], h_c11[0][0], h_c22[0][0], h_c33[0][0], h_c44[0][0], h_c55[0][0], h_c66[0][0], h_c12[0][0], h_c13[0][0], h_c23[0][0], h_vp[0][0], h_vs[0][0]};

  sinc_interp3d_n(narray, input, output, sinc_table, ntab, lsinc,
    fullfdm->nzpad, fullfdm->oz, fullfdm->dz,
    fullfdm->nxpad, fullfdm->ox, fullfdm->dx,
    fullfdm->nypad, fullfdm->oy, fullfdm->dy,
    newfdm->nzpad, newfdm->oz, newfdm->dz,
    newfdm->nxpad, newfdm->ox, newfdm->dx,
    newfdm->nypad, newfdm->oy, newfdm->dy);

  gettimeofday(&stop, NULL);
  float elapse = stop.tv_sec - start.tv_sec + (stop.tv_usec - start.tv_usec) * 1e-6;
  fprintf(stderr, "time for interpolate density and velocities: %.2f\n", elapse);
}


static void scatter_to_gpu(const fdm3d &fdm, float *h_ux, float *h_uy, float *h_uz, float **d_uox, float **d_uoy, float **d_uoz, float ***uox, float ***uoy, float ***uoz, int nyinterior, int ngpu)
{
  for (int y = 0; y < nyinterior; y++){
    for (int z = 0; z < fdm->nzpad; z++){
      for (int x = 0; x < fdm->nxpad; x++){
         h_ux[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x] = uox[y][x][z];
         h_uy[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x] = uoy[y][x][z];
         h_uz[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x] = uoz[y][x][z];
      }
    }
  }
  cudaMemcpy(d_uox[0], h_ux, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
  cudaMemcpy(d_uoy[0], h_uy, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
  cudaMemcpy(d_uoz[0], h_uz, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);


  // write other GPU's portions of wavefield data into output arrays
  for (int g = 1; g < ngpu; g++){

    for (int y = 0; y < nyinterior; y++){
      for (int z = 0; z < fdm->nzpad; z++){
        for (int x = 0; x < fdm->nxpad; x++){
           h_ux[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x] = uox[g * nyinterior + y][x][z];
           h_uy[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x] = uoy[g * nyinterior + y][x][z];
           h_uz[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x] = uoz[g * nyinterior + y][x][z];
        }
      }
    }

    cudaMemcpy(d_uox[g] + 4 * fdm->nzpad * fdm->nxpad, h_ux, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_uoy[g] + 4 * fdm->nzpad * fdm->nxpad, h_uy, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_uoz[g] + 4 * fdm->nzpad * fdm->nxpad, h_uz, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
  }
}

static void gather_from_gpu(const fdm3d &fdm, float *h_ux, float *h_uy, float *h_uz, float **d_uox, float **d_uoy, float **d_uoz, float ***uox, float ***uoy, float ***uoz, int nyinterior, int ngpu)
{
  //sf_warning("%s: cudaMemcpy", __FUNCTION__);
  cudaMemcpy(h_ux, d_uox[0], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
  cudaMemcpy(h_uy, d_uoy[0], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
  cudaMemcpy(h_uz, d_uoz[0], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);

  for (int y = 0; y < nyinterior; y++){
    for (int z = 0; z < fdm->nzpad; z++){
      for (int x = 0; x < fdm->nxpad; x++){
        uox[y][x][z] = h_ux[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x];
        uoy[y][x][z] = h_uy[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x];
        uoz[y][x][z] = h_uz[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x];
      }
    }
  }


  // write other GPU's portions of wavefield data into output arrays
  for (int g = 1; g < ngpu; g++){
    cudaMemcpy(h_ux, d_uox[g] + 4 * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(h_uy, d_uoy[g] + 4 * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(h_uz, d_uoz[g] + 4 * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);

    for (int y = 0; y < nyinterior; y++){
      for (int z = 0; z < fdm->nzpad; z++){
        for (int x = 0; x < fdm->nxpad; x++){
          uox[g * nyinterior + y][x][z] = h_ux[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x];
          uoy[g * nyinterior + y][x][z] = h_uy[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x];
          uoz[g * nyinterior + y][x][z] = h_uz[y * fdm->nzpad * fdm->nxpad + z * fdm->nxpad + x];
        }
      }
    }
  }
}

static void init_host_den_vel(const fdm3d &fdm, float ***full_h_ro, float ***full_h_c11, float ***full_h_c22, float ***full_h_c33, float ***full_h_c44, float ***full_h_c55, float ***full_h_c66, float ***full_h_c12, float ***full_h_c13, float ***full_h_c23, float ***full_h_vp, float ***full_h_vs, float ***&h_ro, float ***&h_c11, float ***&h_c22, float ***&h_c33, float ***&h_c44, float ***&h_c55, float ***&h_c66, float ***&h_c12, float ***&h_c13, float ***&h_c23, float ***&h_vp, float ***&h_vs)
{
 assert(h_ro  = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c11 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c22 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c33 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c44 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c55 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c66 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c12 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c13 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_c23 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_vp = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));
 assert(h_vs = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad));

#pragma omp parallel for
  for (int iy = 0; iy < fdm->nypad; iy++) {
    for (int ix = 0; ix < fdm->nxpad; ix++) {
      for (int iz = 0; iz < fdm->nzpad; iz++) {
        h_ro[iy][ix][iz] = full_h_ro[iy][ix][iz];
        h_c11[iy][ix][iz] = full_h_c11[iy][ix][iz];
        h_c22[iy][ix][iz] = full_h_c22[iy][ix][iz];
        h_c33[iy][ix][iz] = full_h_c33[iy][ix][iz];
        h_c44[iy][ix][iz] = full_h_c44[iy][ix][iz];
        h_c55[iy][ix][iz] = full_h_c55[iy][ix][iz];
        h_c66[iy][ix][iz] = full_h_c66[iy][ix][iz];
        h_c12[iy][ix][iz] = full_h_c12[iy][ix][iz];
        h_c13[iy][ix][iz] = full_h_c13[iy][ix][iz];
        h_c23[iy][ix][iz] = full_h_c23[iy][ix][iz];
        h_vp[iy][ix][iz] = full_h_vp[iy][ix][iz];
        h_vs[iy][ix][iz] = full_h_vs[iy][ix][iz];
      }
    }
  }
}

static void release_host_den_vel(float ***&h_ro, float ***&h_c11, float ***&h_c22, float ***&h_c33, float ***&h_c44, float ***&h_c55, float ***&h_c66, float ***&h_c12, float ***&h_c13, float ***&h_c23)
{
  free(**h_ro); free(*h_ro); free(h_ro);
  free(**h_c11); free(*h_c11); free(h_c11);
  free(**h_c22); free(*h_c22); free(h_c22);
  free(**h_c33); free(*h_c33); free(h_c33);
  free(**h_c44); free(*h_c44); free(h_c44);
  free(**h_c55); free(*h_c55); free(h_c55);
  free(**h_c66); free(*h_c66); free(h_c66);
  free(**h_c12); free(*h_c12); free(h_c12);
  free(**h_c13); free(*h_c13); free(h_c13);
  free(**h_c23); free(*h_c23); free(h_c23);
}


static void interp_host_umo_patch_n(const fdm3d &oldfdm, const fdm3d &newfdm, const float *sinc_table, int ntab, int lsinc, float ***&h_umx, float ***&h_uox,  float ***&h_umy,  float ***&h_uoy,  float ***&h_umz,  float ***&h_uoz)
{
  if (checksame(oldfdm, newfdm)) {
    sf_warning("old and new dimensions for wavefields are the same, don't need interpolatin");
    return;
  }

  struct timeval start, stop;
  gettimeofday(&start, NULL);

  float ***n_umx = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  float ***n_umy = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  float ***n_umz = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  float ***n_uox = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  float ***n_uoy = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);
  float ***n_uoz = sf_floatalloc3(newfdm->nzpad, newfdm->nxpad, newfdm->nypad);

  int narray = 6; /// 6 arrays
  float *input[]  = {h_umx[0][0], h_umy[0][0], h_umz[0][0], h_uox[0][0], h_uoy[0][0], h_uoz[0][0] };
  float *output[] = {n_umx[0][0], n_umy[0][0], n_umz[0][0], n_uox[0][0], n_uoy[0][0], n_uoz[0][0] };
  sinc_interp3d_n(narray, input, output, sinc_table, ntab, lsinc,
    oldfdm->nzpad, oldfdm->oz, oldfdm->dz,
    oldfdm->nxpad, oldfdm->ox, oldfdm->dx,
    oldfdm->nypad, oldfdm->oy, oldfdm->dy,
    newfdm->nzpad, newfdm->oz, newfdm->dz,
    newfdm->nxpad, newfdm->ox, newfdm->dx,
    newfdm->nypad, newfdm->oy, newfdm->dy);

  free(**h_umx); free(*h_umx); free(h_umx); h_umx = n_umx;
  free(**h_umy); free(*h_umy); free(h_umy); h_umy = n_umy;
  free(**h_umz); free(*h_umz); free(h_umz); h_umz = n_umz;
  free(**h_uox); free(*h_uox); free(h_uox); h_uox = n_uox;
  free(**h_uoy); free(*h_uoy); free(h_uoy); h_uoy = n_uoy;
  free(**h_uoz); free(*h_uoz); free(h_uoz); h_uoz = n_uoz;

  gettimeofday(&stop, NULL);
  float elapse = stop.tv_sec - start.tv_sec + (stop.tv_usec - start.tv_usec) * 1e-6;
  fprintf(stderr, "time for interpolate wavefields: %.2f\n", elapse);
}

static fdm3d clonefdm(const fdm3d &fdm)
{
  sf_axis az = sf_maxa(fdm->nz, fdm->oz, fdm->dz);
  sf_axis ax = sf_maxa(fdm->nx, fdm->ox, fdm->dx);
  sf_axis ay = sf_maxa(fdm->ny, fdm->oy, fdm->dy);

  return fdutil3d_init(fdm->verb,fdm->free,az,ax,ay,fdm->nb,fdm->ompchunk);
}

static void init_host_umo(const fdm3d &fdm, float ***&h_umx, float ***&h_uox,  float ***&h_umy,  float ***&h_uoy,  float ***&h_umz,  float ***&h_uoz, float ***&h_vp, float ***&h_vs)
{
  int n1 = fdm->nzpad; int n2 = fdm->nxpad; int n3 = fdm->nypad;
  int bytes = n1 * n2 * n3 * sizeof(float);

  h_umz = sf_floatalloc3(n1, n2, n3);
  h_umx = sf_floatalloc3(n1, n2, n3);
  h_umy = sf_floatalloc3(n1, n2, n3);
  h_uoz = sf_floatalloc3(n1, n2, n3);
  h_uox = sf_floatalloc3(n1, n2, n3);
  h_uoy = sf_floatalloc3(n1, n2, n3);
  h_vp = sf_floatalloc3(n1, n2, n3);
  h_vs = sf_floatalloc3(n1, n2, n3);

#pragma omp parallel for
  for (int iy = 0; iy < n3; iy++) {
    for (int ix = 0; ix < n2; ix++) {
      for (int iz = 0; iz < n1; iz++) {
        h_umz[iy][ix][iz] = 0;
        h_umx[iy][ix][iz] = 0;
        h_umy[iy][ix][iz] = 0;
        h_uoz[iy][ix][iz] = 0;
        h_uox[iy][ix][iz] = 0;
        h_uoy[iy][ix][iz] = 0;
        h_uoy[iy][ix][iz] = 0;
        h_uoy[iy][ix][iz] = 0;
      }
    }
  }
}

static void release_host_umo(float ***&h_umx, float ***&h_uox,  float ***&h_umy,  float ***&h_uoy,  float ***&h_umz,  float ***&h_uoz)
{
  free(**h_umx); free(*h_umx); free(h_umx);
  free(**h_umz); free(*h_umz); free(h_umz);
  free(**h_umy); free(*h_umy); free(h_umy);
  free(**h_uox); free(*h_uox); free(h_uox);
  free(**h_uoz); free(*h_uoz); free(h_uoz);
  free(**h_uoy); free(*h_uoy); free(h_uoy);
}


// checks the current GPU device for an error flag and prints to stderr
static void sf_check_gpu_error (const char *msg) {
    cudaError_t err = cudaGetLastError ();
     if (cudaSuccess != err)
        sf_error ("Cuda error: %s: %s", msg, cudaGetErrorString (err));
}

static void update_axis(const fdm3d &fdm, sf_axis &az, sf_axis &ax, sf_axis &ay, bool verb) {
  //sf_warning("extended dimensions:");
  sf_setn(az,fdm->nzpad); sf_seto(az,fdm->ozpad); if(verb) sf_raxa(az);
  sf_setn(ax,fdm->nxpad); sf_seto(ax,fdm->oxpad); if(verb) sf_raxa(ax);
  sf_setn(ay,fdm->nypad); sf_seto(ay,fdm->oypad); if(verb) sf_raxa(ay);
}

static float **setup_bell(int nbell, int ngpu)
{
  /*------------------------------------------------------------*/
  /* setup bell for source injection smoothing */
  if (nbell * 2 + 1 > 32){
    sf_error("nbell must be <= 15\n");
  }

  float *h_bell;
  h_bell = (float*)malloc((2*nbell+1)*(2*nbell+1)*(2*nbell+1)*sizeof(float));

  float s = 0.5*nbell;
  for (int iy=-nbell;iy<=nbell;iy++) {
    for (int ix=-nbell;ix<=nbell;ix++) {
      for(int iz=-nbell;iz<=nbell;iz++) {
        h_bell[(iy + nbell) * (2*nbell+1) * (2*nbell+1) + (iz + nbell) * (2*nbell+1) + (ix + nbell)] = exp(-(iz*iz+ix*ix+iy*iy)/s);
      }
    }
  }

  // copy bell coeficients to the GPUs
  float **d_bell = (float**)malloc(ngpu*sizeof(float*));
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_bell[g], (2*nbell+1)*(2*nbell+1)*(2*nbell+1)*sizeof(float));
    sf_check_gpu_error("cudaMalloc d_bell");
    cudaMemcpy(d_bell[g], h_bell, (2*nbell+1)*(2*nbell+1)*(2*nbell+1)*sizeof(float), cudaMemcpyDefault);
    sf_check_gpu_error("copy d_bell to device");
  }

  free(h_bell);

  return d_bell;
  /*------------------------------------------------------------*/
}
static void setup_output_data(sf_file &Fdat, sf_axis &at, const sf_axis &ar, const sf_axis &ac, int nt, int jdata, float dt)
{
  /*------------------------------------------------------------*/
  /* setup output data files and arrays */
  sf_oaxa(Fdat,ar,1);
  sf_oaxa(Fdat,ac,2);

  sf_setn(at,nt/jdata);
  sf_setd(at,dt*jdata);
  sf_oaxa(Fdat,at,3);
}

static void set_output_wfd_time_block(sf_file &Fwfl, sf_axis &at, const sf_axis &az, const sf_axis &ax, const sf_axis &ay, const sf_axis &ac, int nt, int total_iter, float dt, int jsnap, bool verb)
{
  int ntsnap=0;
  for(int it=total_iter; it<total_iter+nt; it++) {
    if(it%jsnap==0) ntsnap++;
  }
  sf_setn(at,  ntsnap);
  sf_seto(at, total_iter * dt);
  sf_setd(at,dt*jsnap);
  if(verb) sf_raxa(at);

  sf_oaxa(Fwfl,az,1);
  sf_oaxa(Fwfl,ax,2);
  sf_oaxa(Fwfl,ay,3);
  sf_oaxa(Fwfl,ac, 4);
  sf_oaxa(Fwfl,at, 5);
}
static void alloc_wlf(const fdm3d &fdm, float *** &uoz, float *** &uox, float *** &uoy, float *&h_uoz, float *&h_uox, float *&h_uoy, float ***&uc, int nyinterior)
{
    // Used to accumulate wavefield data from other GPUs
    uoz=sf_floatalloc3(fdm->nzpad,fdm->nxpad,fdm->nypad);
    uox=sf_floatalloc3(fdm->nzpad,fdm->nxpad,fdm->nypad);
    uoy=sf_floatalloc3(fdm->nzpad,fdm->nxpad,fdm->nypad);
    h_uoz = (float*)malloc(nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    h_uox = (float*)malloc(nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    h_uoy = (float*)malloc(nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));

    //uc=sf_floatalloc3(sf_n(az),sf_n(ax),sf_n(ay));
    uc=sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);

}
static float *init_wavelet(sf_file &Fwav, int ns, int nc, int nt)
{
  /*------------------------------------------------------------*/
  /* read source wavelet(s) and copy to each GPU (into d_ww) */
  float ***ww=sf_floatalloc3(ns,nc,nt);
  sf_floatread(ww[0][0],nt*nc*ns,Fwav);

  float *h_ww = (float*)malloc(ns*nc*nt*sizeof(float));
  for (int t = 0; t < nt; t++){
    for (int c = 0; c < nc; c++){
      for (int s = 0; s < ns; s++){
        h_ww[t * nc * ns + c * ns + s]=ww[t][c][s];
      }
    }
  }


  free(**ww); free(*ww); free(ww);
  return h_ww;
  /*------------------------------------------------------------*/
}
static float **copy_wavelet(const float *h_ww, int ns, int nc, int nt, int ngpu) {
  float **d_ww = (float**)malloc(ngpu*sizeof(float*));
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_ww[g], ns*nc*nt*sizeof(float));
    sf_check_gpu_error("cudaMalloc source wavelet to device");
    cudaMemcpy(d_ww[g], h_ww, ns*nc*nt*sizeof(float), cudaMemcpyDefault);
    sf_check_gpu_error("copy source wavelet to device");
  }

  return d_ww;
}
static void setup_output_array(float *&h_dd, float *&h_dd_combined, float **&d_dd, int ngpu, int nr, int nc)
{
  /*------------------------------------------------------------*/
  /* data array */
  h_dd = (float*)malloc(nr * nc * sizeof(float));
  h_dd_combined = (float*)malloc(nr * nc * sizeof(float));

  d_dd = (float**)malloc(ngpu*sizeof(float*));
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_dd[g], nr*nc*sizeof(float));
    sf_check_gpu_error("allocate data arrays");
  }
  /*------------------------------------------------------------*/

}
static void setup_src_rcv_cord(sf_file &Fsou, sf_file &Frec, pt3d *&ss, pt3d *&rr, int ns, int nr)
{
  /*------------------------------------------------------------*/
  /* setup source/receiver coordinates */
  ss = (pt3d*) sf_alloc(ns,sizeof(*ss));
  rr = (pt3d*) sf_alloc(nr,sizeof(*rr));

  pt3dread1(Fsou,ss,ns,3); /* read (x,y,z) coordinates */
  pt3dread1(Frec,rr,nr,3); /* read (x,y,z) coordinates */

}
static void setup_interp_cooef_receiver(float **&d_Rw000, float **&d_Rw001, float **&d_Rw010, float **&d_Rw011, float **&d_Rw100, float **&d_Rw101, float **&d_Rw110, float **&d_Rw111, int **&d_Rjz, int **&d_Rjx, int **&d_Rjy, const fdm3d &fdm, pt3d *rr, int nr, int ngpu)
{
  /* calculate 3d linear interpolation coefficients for receiver locations and copy to each GPU*/
  lint3d cr = lint3d_make(nr,rr,fdm);
  d_Rw000 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw001 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw010 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw011 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw100 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw101 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw110 = (float**)malloc(ngpu*sizeof(float*));
  d_Rw111 = (float**)malloc(ngpu*sizeof(float*));

  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_Rw000[g], nr * sizeof(float));
    cudaMalloc(&d_Rw001[g], nr * sizeof(float));
    cudaMalloc(&d_Rw010[g], nr * sizeof(float));
    cudaMalloc(&d_Rw011[g], nr * sizeof(float));
    cudaMalloc(&d_Rw100[g], nr * sizeof(float));
    cudaMalloc(&d_Rw101[g], nr * sizeof(float));
    cudaMalloc(&d_Rw110[g], nr * sizeof(float));
    cudaMalloc(&d_Rw111[g], nr * sizeof(float));
    sf_check_gpu_error("cudaMalloc receiver interpolation coefficients to device");
    cudaMemcpy(d_Rw000[g], cr->w000, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw001[g], cr->w001, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw010[g], cr->w010, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw011[g], cr->w011, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw100[g], cr->w100, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw101[g], cr->w101, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw110[g], cr->w110, nr * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Rw111[g], cr->w111, nr * sizeof(float), cudaMemcpyDefault);
    sf_check_gpu_error("copy receiver interpolation coefficients to device");

  }

  // z, x, and y coordinates of each receiver
  d_Rjz = (int**)malloc(ngpu*sizeof(int*));
  d_Rjx = (int**)malloc(ngpu*sizeof(int*));
  d_Rjy = (int**)malloc(ngpu*sizeof(int*));
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_Rjz[g], nr * sizeof(int));
    cudaMalloc(&d_Rjx[g], nr * sizeof(int));
    cudaMalloc(&d_Rjy[g], nr * sizeof(int));
    sf_check_gpu_error("cudaMalloc receiver coords to device");
    cudaMemcpy(d_Rjz[g], cr->jz, nr * sizeof(int), cudaMemcpyDefault);
    cudaMemcpy(d_Rjx[g], cr->jx, nr * sizeof(int), cudaMemcpyDefault);
    cudaMemcpy(d_Rjy[g], cr->jy, nr * sizeof(int), cudaMemcpyDefault);
    sf_check_gpu_error("copy receiver coords to device");
  }
}
static void setup_interp_cooef_source(float **&d_Sw000, float **&d_Sw001, float **&d_Sw010, float **&d_Sw011, float **&d_Sw100, float **&d_Sw101, float **&d_Sw110, float **&d_Sw111, int **&d_Sjz, int **&d_Sjx, int **&d_Sjy, const fdm3d &fdm, pt3d *ss, int ns, int ngpu)
{
  /* calculate 3d linear interpolation coefficients for source locations and copy to each GPU*/
  lint3d cs = lint3d_make(ns,ss,fdm);
  for (int i = 0; i < ns; i++) {
    sf_warning("cs->jz[%d]: %d, cs->jx[%d]: %d, cs->jy[%d]: %d", i, cs->jz[i], i, cs->jx[i], i, cs->jy[i]);
  }

  d_Sw000 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw001 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw010 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw011 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw100 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw101 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw110 = (float**)malloc(ngpu*sizeof(float*));
  d_Sw111 = (float**)malloc(ngpu*sizeof(float*));

  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_Sw000[g], ns * sizeof(float));
    cudaMalloc(&d_Sw001[g], ns * sizeof(float));
    cudaMalloc(&d_Sw010[g], ns * sizeof(float));
    cudaMalloc(&d_Sw011[g], ns * sizeof(float));
    cudaMalloc(&d_Sw100[g], ns * sizeof(float));
    cudaMalloc(&d_Sw101[g], ns * sizeof(float));
    cudaMalloc(&d_Sw110[g], ns * sizeof(float));
    cudaMalloc(&d_Sw111[g], ns * sizeof(float));
    sf_check_gpu_error("cudaMalloc source interpolation coeficients to device");
    cudaMemcpy(d_Sw000[g], cs->w000, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw001[g], cs->w001, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw010[g], cs->w010, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw011[g], cs->w011, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw100[g], cs->w100, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw101[g], cs->w101, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw110[g], cs->w110, ns * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_Sw111[g], cs->w111, ns * sizeof(float), cudaMemcpyDefault);
    sf_check_gpu_error("copy source interpolation coeficients to device");

  }

  // z, x, and y coordinates of each source
  d_Sjz = (int**)malloc(ngpu*sizeof(int*));
  d_Sjx = (int**)malloc(ngpu*sizeof(int*));
  d_Sjy = (int**)malloc(ngpu*sizeof(int*));
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_Sjz[g], ns * sizeof(int));
    cudaMalloc(&d_Sjx[g], ns * sizeof(int));
    cudaMalloc(&d_Sjy[g], ns * sizeof(int));
    sf_check_gpu_error("cudaMalloc source coords to device");
    cudaMemcpy(d_Sjz[g], cs->jz, ns * sizeof(int), cudaMemcpyDefault);
    cudaMemcpy(d_Sjx[g], cs->jx, ns * sizeof(int), cudaMemcpyDefault);
    cudaMemcpy(d_Sjy[g], cs->jy, ns * sizeof(int), cudaMemcpyDefault);
    sf_check_gpu_error("copy source coords to device");
  }

}
static void setup_fd_cooef(const fdm3d &fdm, float &idz, float &idx, float &idy)
{
  /*------------------------------------------------------------*/
  /* setup FD coefficients */
  idz = 1/fdm->dz;;
  idx = 1/fdm->dx;
  idy = 1/fdm->dy;
  /*------------------------------------------------------------*/
}

static void read_density_velocity(sf_file &Fden, sf_file &Fccc, const fdm3d &fdm, float ***&h_ro, float ***&h_c11, float ***&h_c22, float ***&h_c33, float ***&h_c44, float ***&h_c55, float ***&h_c66, float ***&h_c12, float ***&h_c13, float ***&h_c23, int nz, int nx, int ny)
{
  /*------------------------------------------------------------*/
  /* read in model density and stiffness arrays */
  float ***tt1 = sf_floatalloc3(nz, nx, ny);

  /* input density */
  h_ro = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fden);     expand_cpu(tt1[0][0], h_ro[0][0], fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);

  /* input stiffness */
  h_c11 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c22 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c33 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c44 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c55 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c66 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c12 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c13 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  h_c23 = sf_floatalloc3(fdm->nzpad, fdm->nxpad, fdm->nypad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c11[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c22[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c33[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c44[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c55[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c66[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c12[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c13[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  sf_floatread(tt1[0][0],nz*nx*ny,Fccc);    expand_cpu(tt1[0][0],h_c23[0][0],fdm->nb, nx, fdm->nxpad, ny, fdm->nypad, nz, fdm->nzpad);
  free(**tt1); free(*tt1); free(tt1);
}

static void copy_den_vel_to_dev(const fdm3d &fdm, float **&d_ro , float **&d_c11, float **&d_c22, float **&d_c33, float **&d_c44, float **&d_c55, float **&d_c66, float **&d_c12, float **&d_c13, float **&d_c23, float **&d_vp, float **&d_vs, const float *h_ro, const float *h_c11, const float *h_c22, const float *h_c33, const float *h_c44, const float *h_c55, const float *h_c66, const float *h_c12, const float *h_c13, const float *h_c23, const float *h_vp, const float *h_vs, int nyinterior, int ngpu)
{
  d_ro = (float**)malloc(ngpu*sizeof(float*));
  d_c11 = (float**)malloc(ngpu*sizeof(float*));
  d_c22 = (float**)malloc(ngpu*sizeof(float*));
  d_c33 = (float**)malloc(ngpu*sizeof(float*));
  d_c44 = (float**)malloc(ngpu*sizeof(float*));
  d_c55 = (float**)malloc(ngpu*sizeof(float*));
  d_c66 = (float**)malloc(ngpu*sizeof(float*));
  d_c12 = (float**)malloc(ngpu*sizeof(float*));
  d_c13 = (float**)malloc(ngpu*sizeof(float*));
  d_c23 = (float**)malloc(ngpu*sizeof(float*));
  d_vp = (float**)malloc(ngpu*sizeof(float*));
  d_vs = (float**)malloc(ngpu*sizeof(float*));

  // allocate density and stiffness sub-domain arrays on each GPU and copy the data
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaMalloc(&d_ro[g] , nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c11[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c22[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c33[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c44[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c55[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c66[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c12[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c13[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_c23[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_vp[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_vs[g], nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float));
    sf_check_gpu_error("cudaMalloc density and stiffness to device");

    cudaMemcpy(d_ro[g] , h_ro  + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c11[g], h_c11 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c22[g], h_c22 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c33[g], h_c33 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c44[g], h_c44 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c55[g], h_c55 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c66[g], h_c66 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c12[g], h_c12 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c13[g], h_c13 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_c23[g], h_c23 + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_vp[g],   h_vp + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    cudaMemcpy(d_vs[g],   h_vs + g * nyinterior * fdm->nzpad * fdm->nxpad, nyinterior * fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);
    sf_check_gpu_error("copy density and stiffness to device");

  }

}

static void setup_boundary(const fdm3d fdm, float **&d_bzl_s, float **&d_bzh_s, float **&d_bxl_s, float **&d_bxh_s, float **&d_byl_s, float **&d_byh_s, const float *h_ro, const float *h_c55, float &spo, int nyinterior, int ngpu, float dt, bool dabc)
{
  /*------------------------------------------------------------*/
  /* Boundary condition setup */
  d_bzl_s = (float**)malloc(ngpu*sizeof(float*));
  d_bzh_s = (float**)malloc(ngpu*sizeof(float*));
  d_bxl_s = (float**)malloc(ngpu*sizeof(float*));
  d_bxh_s = (float**)malloc(ngpu*sizeof(float*));
  d_byl_s = (float**)malloc(ngpu*sizeof(float*));
  d_byh_s = (float**)malloc(ngpu*sizeof(float*));

  float *h_bzl_s, *h_bzh_s;
  float *h_bxl_s, *h_bxh_s;
  float *h_byl_s, *h_byh_s;

  spo = 0;
  int nb = fdm->nb;
  if(dabc) {

    /* one-way abc setup   */
    float d;
    float *vs1 = (float*)malloc(fdm->nzpad * fdm->nxpad * fdm->nypad * sizeof(float));

    for (int iy = 0; iy < fdm->nypad; iy++) {
      for (int ix = 0; ix < fdm->nxpad; ix++) {
        for (int iz = 0; iz < fdm->nzpad; iz++) {
          vs1[iy * fdm->nzpad * fdm->nxpad + iz * fdm->nxpad + ix] = sqrt(h_c55[iy * fdm->nxpad * fdm->nzpad + iz * fdm->nxpad + ix] / h_ro[iy * fdm->nxpad * fdm->nzpad + iz * fdm->nxpad + ix]);
        }
      }
    }

    h_bzl_s = (float*)malloc(fdm->nxpad * nyinterior * sizeof(float));
    h_bzh_s = (float*)malloc(fdm->nxpad * nyinterior * sizeof(float));
    for (int g = 0; g < ngpu; g++){
      cudaSetDevice(g);
      for (int ix = 0; ix < fdm->nxpad; ix++){
        for (int iy = 0; iy < nyinterior; iy++){
          d = vs1[(g * nyinterior + iy) * fdm->nzpad * fdm->nxpad + NOP * fdm->nxpad + ix] * dt/fdm->dz;
          h_bzl_s[iy * fdm->nxpad + ix] = (1-d)/(1+d);
          d = vs1[(g * nyinterior + iy) * fdm->nzpad * fdm->nxpad + (fdm->nzpad-NOP-1) * fdm->nxpad + ix] * dt/fdm->dz;
          h_bzh_s[iy * fdm->nxpad + ix] = (1-d)/(1+d);
        }
      }

      cudaMalloc(&d_bzl_s[g], fdm->nxpad * nyinterior * sizeof(float));
      cudaMalloc(&d_bzh_s[g], fdm->nxpad * nyinterior * sizeof(float));
      cudaMemcpy(d_bzl_s[g], h_bzl_s, fdm->nxpad * nyinterior * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_bzh_s[g], h_bzh_s, fdm->nxpad * nyinterior * sizeof(float), cudaMemcpyDefault);
    }


    h_bxl_s = (float*)malloc(fdm->nzpad * nyinterior * sizeof(float));
    h_bxh_s = (float*)malloc(fdm->nzpad * nyinterior * sizeof(float));
    for (int g = 0; g < ngpu; g++){
      cudaSetDevice(g);
      for (int iz = 0; iz < fdm->nzpad; iz++){
        for (int iy = 0; iy < nyinterior; iy++){
          d = vs1[(g * nyinterior + iy) * fdm->nzpad * fdm->nxpad + iz * fdm->nxpad + NOP] *dt/fdm->dx;
          h_bxl_s[iy * fdm->nzpad + iz] = (1-d)/(1+d);
          d = vs1[(g * nyinterior + iy) * fdm->nzpad * fdm->nxpad + iz * fdm->nxpad + (fdm->nxpad-NOP-1)] *dt/fdm->dx;
          h_bxh_s[iy * fdm->nzpad + iz] = (1-d)/(1+d);
        }
      }
      cudaMalloc(&d_bxl_s[g], fdm->nzpad * nyinterior * sizeof(float));
      cudaMalloc(&d_bxh_s[g], fdm->nzpad * nyinterior * sizeof(float));
      cudaMemcpy(d_bxl_s[g], h_bxl_s, fdm->nzpad * nyinterior * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_bxh_s[g], h_bxh_s, fdm->nzpad * nyinterior * sizeof(float), cudaMemcpyDefault);
    }


    h_byl_s = (float*)malloc(fdm->nzpad * fdm->nxpad * sizeof(float));
    h_byh_s = (float*)malloc(fdm->nzpad * fdm->nxpad * sizeof(float));
    for (int ix = 0; ix < fdm->nxpad; ix++){
      for (int iz = 0; iz < fdm->nzpad; iz++){
        d = vs1[NOP * fdm->nzpad * fdm->nxpad + iz * fdm->nxpad + ix] *dt/fdm->dy;
        h_byl_s[ix * fdm->nzpad + iz] = (1-d)/(1+d);
        d = vs1[(fdm->nypad-NOP-1) * fdm->nzpad * fdm->nxpad + iz * fdm->nxpad + ix] *dt/fdm->dy;
        h_byh_s[ix * fdm->nzpad + iz] = (1-d)/(1+d);
      }
    }
    cudaSetDevice(0);
    cudaMalloc(&d_byl_s[0], fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemcpy(d_byl_s[0], h_byl_s, fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);

    cudaSetDevice(ngpu-1);
    cudaMalloc(&d_byh_s[ngpu-1], fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemcpy(d_byh_s[ngpu-1], h_byh_s, fdm->nzpad * fdm->nxpad * sizeof(float), cudaMemcpyDefault);

    sf_check_gpu_error("set up ABC coefficients");

    /* sponge set up */
    // sponge coefficients are calculated inside the sponge kernel on GPU based on spo
    spo = (sqrt(2.0) * 4.0f * nb);

    free(h_bzl_s); free(h_bzh_s);
    free(h_bxl_s); free(h_bxh_s);
    free(h_byl_s); free(h_byh_s);
    free(vs1);
  }
  /*------------------------------------------------------------*/
}

static void init_wfd_array(const fdm3d &fdm, float *h_ux, float *h_uy, float *h_uz, float ***h_umx, float ***h_uox,  float ***h_umy,  float ***h_uoy,  float ***h_umz,  float ***h_uoz, float **&d_umx, float **&d_uox, float **&d_upx, float **&d_uax, float **&d_utx, float **&d_umy, float **&d_uoy, float **&d_upy, float **&d_uay, float **&d_uty, float **&d_umz, float **&d_uoz, float **&d_upz, float **&d_uaz, float **&d_utz, float **&d_tzz, float **&d_txx, float **&d_tyy, float **&d_txy, float **&d_tyz, float **&d_tzx, const int *nylocal, int ngpu, int nyinterior)
{
  /*------------------------------------------------------------*/
  /* displacement: um = U @ t-1; uo = U @ t; up = U @ t+1 */
  d_umx = (float **)malloc(ngpu*sizeof(float*));
  d_uox = (float **)malloc(ngpu*sizeof(float*));
  d_upx = (float **)malloc(ngpu*sizeof(float*));
  d_uax = (float **)malloc(ngpu*sizeof(float*));
  d_utx = (float **)malloc(ngpu*sizeof(float*));

  d_umy = (float **)malloc(ngpu*sizeof(float*));
  d_uoy = (float **)malloc(ngpu*sizeof(float*));
  d_upy = (float **)malloc(ngpu*sizeof(float*));
  d_uay = (float **)malloc(ngpu*sizeof(float*));
  d_uty = (float **)malloc(ngpu*sizeof(float*));

  d_umz = (float **)malloc(ngpu*sizeof(float*));
  d_uoz = (float **)malloc(ngpu*sizeof(float*));
  d_upz = (float **)malloc(ngpu*sizeof(float*));
  d_uaz = (float **)malloc(ngpu*sizeof(float*));
  d_utz = (float **)malloc(ngpu*sizeof(float*));

  d_tzz = (float **)malloc(ngpu*sizeof(float*));
  d_txx = (float **)malloc(ngpu*sizeof(float*));
  d_tyy = (float **)malloc(ngpu*sizeof(float*));
  d_txy = (float **)malloc(ngpu*sizeof(float*));
  d_tyz = (float **)malloc(ngpu*sizeof(float*));
  d_tzx = (float **)malloc(ngpu*sizeof(float*));

  // allocate and initialize displacement, accel, and stress/strain arrasys to 0 on each GPU
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);

    cudaMalloc(&d_umx[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_uox[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_upx[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_uax[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    cudaMalloc(&d_umy[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_uoy[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_upy[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_uay[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    cudaMalloc(&d_umz[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_uoz[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_upz[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_uaz[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    cudaMalloc(&d_tzz[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_tyy[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_txx[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_txy[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_tyz[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMalloc(&d_tzx[g], nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    sf_check_gpu_error("allocate grid arrays");


    cudaMemset(d_umx[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_uox[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_upx[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_uax[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    cudaMemset(d_umy[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_uoy[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_upy[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_uay[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    cudaMemset(d_umz[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_uoz[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_upz[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_uaz[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    cudaMemset(d_tzz[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_tyy[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_txx[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_txy[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_tyz[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));
    cudaMemset(d_tzx[g], 0, nylocal[g] * fdm->nzpad * fdm->nxpad * sizeof(float));

    sf_check_gpu_error("initialize grid arrays");
  }

  scatter_to_gpu(fdm, h_ux, h_uy, h_uz, d_umx, d_umy, d_umz, h_umx, h_umy, h_umz, nyinterior, ngpu);
  scatter_to_gpu(fdm, h_ux, h_uy, h_uz, d_uox, d_uoy, d_uoz, h_uox, h_uoy, h_uoz, nyinterior, ngpu);
}
static void precompute(const fdm3d &fdm, float **&d_ro, float dt, int nyinterior, int ngpu)
{
  /*------------------------------------------------------------*/
  /* precompute 1/ro * dt^2                     */
  /*------------------------------------------------------------*/
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    dim3 dimGrid1(ceil(fdm->nxpad/8.0f),ceil(fdm->nzpad/8.0f),ceil(nyinterior/8.0f));
    dim3 dimBlock1(8,8,8);
    computeRo<<<dimGrid1, dimBlock1>>>(d_ro[g], dt, fdm->nxpad, fdm->nzpad, nyinterior);
  }
  sf_check_gpu_error("computeRo Kernel");
}

static void main_loop(sf_file Fwfl, sf_file Fdat, const fdm3d &fdm, float dt, float **d_umx, float **d_uox, float **d_upx, float **d_uax, float **d_utx, float **d_umy, float **d_uoy, float **d_upy, float **d_uay, float **d_uty, float **d_umz, float **d_uoz, float **d_upz, float **d_uaz, float **d_utz, float **d_tzz, float **d_txx, float **d_tyy, float **d_txy, float **d_tyz, float **d_tzx, float **d_c11, float **d_c22, float **d_c33, float **d_c44, float **d_c55, float **d_c66, float **d_c12, float **d_c13, float **d_c23, float **d_vp, float **d_vs, float **d_Sw000, float **d_Sw001, float **d_Sw010, float **d_Sw011, float **d_Sw100, float **d_Sw101, float **d_Sw110, float **d_Sw111, int **d_Sjz, int **d_Sjx, int **d_Sjy, float **d_Rw000, float **d_Rw001, float **d_Rw010, float **d_Rw011, float **d_Rw100, float **d_Rw101, float **d_Rw110, float **d_Rw111, int **d_Rjz, int **d_Rjx, int **d_Rjy, float **d_bell, float **d_ww, float **d_ro, float **d_bzl_s, float **d_bzh_s, float **d_bxl_s, float **d_bxh_s, float **d_byl_s, float **d_byh_s, float *** uoz, float *** uox, float *** uoy, float *h_uz, float *h_ux, float *h_uy, float ***uc, float *h_dd, float *h_dd_combined, float **d_dd, sf_axis az, sf_axis ax, sf_axis ay, const int *nylocal, float spo, float idx, float idy, float idz, int nt, int jsnap, int jdata, int ngpu, int nyinterior, int ns, int nr, int nbell, int nc, bool interp, bool snap, bool fsrf, bool ssou, bool dabc, bool verb, int &total_iter, bool withq, float qp, float qs)
{
  int nb = fdm->nb;
  int nx = fdm->nx;
  int end_iter = total_iter + nt;
  if(verb) fprintf(stderr,"\n");
  struct timeval start, stop;
  float compute_elapsed = 0;
  float io_elapse = 0;

  for (int it=total_iter; it< end_iter; it++, total_iter++) {
    if(verb) fprintf(stderr,"\b\b\b\b\b%d", total_iter);

    gettimeofday(&start, NULL);
    /*------------------------------------------------------------*/
    /* from displacement to strain                                */
    /*    - Compute strains from displacements as in equation 1 */
    /*      - Step #1 (Steps denoted are as in Figure 2)    */
    /*------------------------------------------------------------*/
    for (int g = 0; g < ngpu; g++){
      cudaSetDevice(g);
      dim3 dimGrid2((fdm->nxpad-2*NOP)/24.0f, (fdm->nzpad-2*NOP)/24.0f);
      dim3 dimBlock2(24,24,1);
      dispToStrain<<<dimGrid2, dimBlock2, 32*32*3*sizeof(float)>>>(fdm->nxpad, nylocal[g], fdm->nzpad, d_uox[g], d_uoy[g], d_uoz[g], d_txx[g], d_tyy[g], d_tzz[g], d_txy[g], d_tyz[g], d_tzx[g], idx, idy, idz);
    }
    sf_check_gpu_error("dispToStrain Kernel");

    /*------------------------------------------------------------*/
    /* from strain to stress                                      */
    /*    - Compute stress from strain as in equation 2     */
    /*      - Step #2                     */
    /*------------------------------------------------------------*/
    for (int g = 0; g < ngpu; g++){
      cudaSetDevice(g);
      dim3 dimGrid3(ceil(fdm->nxpad/192.0f), fdm->nzpad, nyinterior);
      dim3 dimBlock3(192,1,1);
      if (!withq) {
        strainToStress<<<dimGrid3, dimBlock3>>>(g, fdm->nxpad, fdm->nzpad, nyinterior, d_c11[g], d_c12[g], d_c13[g], d_c22[g], d_c23[g], d_c33[g], d_c44[g], d_c55[g], d_c66[g], d_txx[g], d_tyy[g], d_tzz[g], d_txy[g], d_tyz[g], d_tzx[g]);
      } else {
        strainToStressQ<<<dimGrid3, dimBlock3>>>(g, fdm->nxpad, fdm->nzpad, nyinterior, dt, d_c11[g], d_c12[g], d_c13[g], d_c22[g], d_c23[g], d_c33[g], d_c44[g], d_c55[g], d_c66[g], d_txx[g], d_tyy[g], d_tzz[g], d_txy[g], d_tyz[g], d_tzx[g], d_vp[g], d_vs[g], qp, qs);
      }
    }
    sf_check_gpu_error("strainToStress Kernel");


    /*------------------------------------------------------------*/
    /* free surface                                               */
    /*    - sets the z-component of stress tensor along the   */
    /*      free surface boundary to 0              */
    /*      - Step #3                     */
    /*------------------------------------------------------------*/
    if(fsrf) {
      for (int g = 0; g < ngpu; g++){
        cudaSetDevice(g);
        dim3 dimGrid4(ceil(fdm->nxpad/8.0f), ceil(fdm->nb/8.0f), ceil(nyinterior/8.0f));
        dim3 dimBlock4(8,8,8);
        freeSurf<<<dimGrid4, dimBlock4>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, fdm->nb, d_tzz[g], d_tyz[g], d_tzx[g]);
      }
      sf_check_gpu_error("freeSurf Kernel");
    }


    /*------------------------------------------------------------*/
    /* inject stress source                                       */
    /*    - Step #4                       */
    /*------------------------------------------------------------*/
    if(ssou) {
      for (int g = 0; g < ngpu; g++){
        cudaSetDevice(g);
        dim3 dimGrid5(ns, 1, 1);
        dim3 dimBlock5(2 * nbell + 1, 2 * nbell + 1, 1);
        lint3d_bell_gpu<<<dimGrid5, dimBlock5>>>(g, it, nc, ns, 0, nbell, fdm->nxpad, nyinterior, fdm->nzpad, d_tzz[g], d_bell[g], d_Sjx[g], d_Sjz[g], d_Sjy[g], d_ww[g], d_Sw000[g], d_Sw001[g], d_Sw010[g], d_Sw011[g], d_Sw100[g], d_Sw101[g], d_Sw110[g], d_Sw111[g]);
        lint3d_bell_gpu<<<dimGrid5, dimBlock5>>>(g, it, nc, ns, 1, nbell, fdm->nxpad, nyinterior, fdm->nzpad, d_txx[g], d_bell[g], d_Sjx[g], d_Sjz[g], d_Sjy[g], d_ww[g], d_Sw000[g], d_Sw001[g], d_Sw010[g], d_Sw011[g], d_Sw100[g], d_Sw101[g], d_Sw110[g], d_Sw111[g]);
        lint3d_bell_gpu<<<dimGrid5, dimBlock5>>>(g, it, nc, ns, 2, nbell, fdm->nxpad, nyinterior, fdm->nzpad, d_tyy[g], d_bell[g], d_Sjx[g], d_Sjz[g], d_Sjy[g], d_ww[g], d_Sw000[g], d_Sw001[g], d_Sw010[g], d_Sw011[g], d_Sw100[g], d_Sw101[g], d_Sw110[g], d_Sw111[g]);
      }
      sf_check_gpu_error("lint3d_bell_gpu Kernel");
    }


    /*------------------------------------------------------------*/
    /* exchange halo regions of d_t arrays between GPUs           */
    /*------------------------------------------------------------*/
    if (ngpu > 1){ // using multiple GPUs, must exchange halo regions between neighboring GPUs

      // high halo region of d_t arrays on GPU 0 to GPU 1
      cudaMemcpy(d_tzz[1], d_tzz[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_tyy[1], d_tyy[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_txx[1], d_txx[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_txy[1], d_txy[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_tyz[1], d_tyz[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_tzx[1], d_tzx[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);

      // exchange halo regions of d_t arrays between all internal GPUs
      for (int g = 1; g < ngpu-1; g++){
        // high halo region of GPU g to low halo region of GPU g+1
        cudaMemcpy(d_tzz[g+1], d_tzz[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_tyy[g+1], d_tyy[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_txx[g+1], d_txx[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_txy[g+1], d_txy[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_tyz[g+1], d_tyz[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_tzx[g+1], d_tzx[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);

        // low halo region of GPU g to high halo region of GPU g-1
        cudaMemcpy(d_tzz[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_tzz[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_tyy[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_tyy[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_txx[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_txx[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_txy[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_txy[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_tyz[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_tyz[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_tzx[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_tzx[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      }

      // low halo region of d_t arrays on GPU (ngpu-1) to GPU (ngpu-2)
      cudaMemcpy(d_tzz[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_tzz[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_tyy[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_tyy[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_txx[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_txx[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_txy[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_txy[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_tyz[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_tyz[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_tzx[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_tzx[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);

    }


    /*------------------------------------------------------------*/
    /* from stress to acceleration  (first term in RHS of eq. 3)  */
    /*    - Step #5                       */
    /*------------------------------------------------------------*/
    for (int g = 0; g < ngpu; g++){
      cudaSetDevice(g);
      dim3 dimGrid6((fdm->nxpad-2*NOP)/24.0f, (fdm->nzpad-2*NOP)/24.0f);
      dim3 dimBlock6(24,24,1);
      stressToAccel<<<dimGrid6, dimBlock6, 32*32*5*sizeof(float)>>>(fdm->nxpad, fdm->nzpad, nylocal[g], idx, idy, idz, d_txx[g], d_tyy[g], d_tzz[g], d_txy[g], d_tzx[g], d_tyz[g], d_uax[g], d_uay[g], d_uaz[g]);
    }
    sf_check_gpu_error("stressToAccel Kernel");


    /*------------------------------------------------------------*/
    /* inject acceleration source  (second term in RHS of eq. 3)  */
    /*    - Step #6                       */
    /*------------------------------------------------------------*/
    if(!ssou) {
      for (int g = 0; g < ngpu; g++){
        cudaSetDevice(g);
        dim3 dimGrid7(ns, 1, 1);
        dim3 dimBlock7(2 * nbell + 1, 2 * nbell + 1, 1);
        lint3d_bell_gpu<<<dimGrid7, dimBlock7>>>(g, it, nc, ns, 0, nbell, fdm->nxpad, nyinterior, fdm->nzpad, d_uaz[g], d_bell[g], d_Sjx[g], d_Sjz[g], d_Sjy[g], d_ww[g], d_Sw000[g], d_Sw001[g], d_Sw010[g], d_Sw011[g], d_Sw100[g], d_Sw101[g], d_Sw110[g], d_Sw111[g]);
        lint3d_bell_gpu<<<dimGrid7, dimBlock7>>>(g, it, nc, ns, 1, nbell, fdm->nxpad, nyinterior, fdm->nzpad, d_uax[g], d_bell[g], d_Sjx[g], d_Sjz[g], d_Sjy[g], d_ww[g], d_Sw000[g], d_Sw001[g], d_Sw010[g], d_Sw011[g], d_Sw100[g], d_Sw101[g], d_Sw110[g], d_Sw111[g]);
        lint3d_bell_gpu<<<dimGrid7, dimBlock7>>>(g, it, nc, ns, 2, nbell, fdm->nxpad, nyinterior, fdm->nzpad, d_uay[g], d_bell[g], d_Sjx[g], d_Sjz[g], d_Sjy[g], d_ww[g], d_Sw000[g], d_Sw001[g], d_Sw010[g], d_Sw011[g], d_Sw100[g], d_Sw101[g], d_Sw110[g], d_Sw111[g]);
      }

      sf_check_gpu_error("lint3d_bell_gpu Kernel");
    }


    /*------------------------------------------------------------*/
    /* step forward in time                                       */
    /*    - Compute forward time step based on acceleration   */
    /*      - Step #7                     */
    /*------------------------------------------------------------*/
    for (int g = 0; g < ngpu; g++){
      cudaSetDevice(g);
      dim3 dimGrid8(ceil(fdm->nxpad/192.0f), fdm->nzpad, nyinterior);
      dim3 dimBlock8(192,1,1);
      stepTime<<<dimGrid8, dimBlock8>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_ro[g], d_uox[g], d_umx[g], d_uax[g], d_upx[g], d_uoy[g], d_umy[g], d_uay[g], d_upy[g], d_uoz[g], d_umz[g], d_uaz[g], d_upz[g]);
    }
    sf_check_gpu_error("stepTime Kernel");


    /* circulate wavefield arrays */
    for (int g = 0; g < ngpu; g++){
      d_utz[g]=d_umz[g]; d_uty[g]=d_umy[g]; d_utx[g]=d_umx[g];
      d_umz[g]=d_uoz[g]; d_umy[g]=d_uoy[g]; d_umx[g]=d_uox[g];
      d_uoz[g]=d_upz[g]; d_uoy[g]=d_upy[g]; d_uox[g]=d_upx[g];
      d_upz[g]=d_utz[g]; d_upy[g]=d_uty[g]; d_upx[g]=d_utx[g];
    }


    /*------------------------------------------------------------*/
    /* apply boundary conditions                                  */
    /*    - Step #8                       */
    /*------------------------------------------------------------*/
    if(dabc) {
      /*---------------------------------------------------------------*/
      /* apply One-way Absorbing BC as in (Clayton and Enquist, 1977)  */
      /*---------------------------------------------------------------*/
      for (int g = 0; g < ngpu; g++){
        cudaSetDevice(g);
        dim3 dimGrid_abc_XY(ceil(fdm->nxpad/32.0f),ceil(nyinterior/32.0f),2);
        dim3 dimBlock_abc_XY(32,32,1);
        abcone3d_apply_XY<<<dimGrid_abc_XY,dimBlock_abc_XY>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_uox[g], d_umx[g], d_bzl_s[g], d_bzh_s[g]);
        abcone3d_apply_XY<<<dimGrid_abc_XY,dimBlock_abc_XY>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_uoy[g], d_umy[g], d_bzl_s[g], d_bzh_s[g]);
        abcone3d_apply_XY<<<dimGrid_abc_XY,dimBlock_abc_XY>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_uoz[g], d_umz[g], d_bzl_s[g], d_bzh_s[g]);

        dim3 dimGrid_abc_ZY(2, ceil(nyinterior/32.0f), ceil(fdm->nzpad/32.0f));
        dim3 dimBlock_abc_ZY(1,32,32);
        abcone3d_apply_ZY<<<dimGrid_abc_ZY,dimBlock_abc_ZY>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_uox[g], d_umx[g], d_bxl_s[g], d_bxh_s[g]);
        abcone3d_apply_ZY<<<dimGrid_abc_ZY,dimBlock_abc_ZY>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_uoy[g], d_umy[g], d_bxl_s[g], d_bxh_s[g]);
        abcone3d_apply_ZY<<<dimGrid_abc_ZY,dimBlock_abc_ZY>>>(g, fdm->nxpad, nyinterior, fdm->nzpad, d_uoz[g], d_umz[g], d_bxl_s[g], d_bxh_s[g]);
      }

      cudaSetDevice(0);
      dim3 dimGrid_abc_XZ(ceil(fdm->nxpad/32.0f),1,ceil(fdm->nzpad/32.0f));
      dim3 dimBlock_abc_XZ(32,1,32);
      abcone3d_apply_XZ_low<<<dimGrid_abc_XZ,dimBlock_abc_XZ>>>(fdm->nxpad, fdm->nzpad, d_uox[0], d_umx[0], d_byl_s[0]);
      abcone3d_apply_XZ_low<<<dimGrid_abc_XZ,dimBlock_abc_XZ>>>(fdm->nxpad, fdm->nzpad, d_uoy[0], d_umy[0], d_byl_s[0]);
      abcone3d_apply_XZ_low<<<dimGrid_abc_XZ,dimBlock_abc_XZ>>>(fdm->nxpad, fdm->nzpad, d_uoz[0], d_umz[0], d_byl_s[0]);

      cudaSetDevice(ngpu-1);
      abcone3d_apply_XZ_high<<<dimGrid_abc_XZ,dimBlock_abc_XZ>>>(fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, d_uox[ngpu-1], d_umx[ngpu-1], d_byh_s[ngpu-1]);
      abcone3d_apply_XZ_high<<<dimGrid_abc_XZ,dimBlock_abc_XZ>>>(fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, d_uoy[ngpu-1], d_umy[ngpu-1], d_byh_s[ngpu-1]);
      abcone3d_apply_XZ_high<<<dimGrid_abc_XZ,dimBlock_abc_XZ>>>(fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, d_uoz[ngpu-1], d_umz[ngpu-1], d_byh_s[ngpu-1]);


      /*---------------------------------------------------------------*/
      /* apply Sponge BC as in (Cerjan, et al., 1985)                  */
      /*---------------------------------------------------------------*/
      for (int g = 0; g < ngpu; g++){
        cudaSetDevice(g);
        dim3 dimGrid_spng_XY(ceil(fdm->nxpad/192.0f),nyinterior,1);
        dim3 dimBlock_spng_XY(192,1,1);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_umz[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_uoz[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_upz[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);

        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_umx[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_uox[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_upx[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);

        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_umy[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_uoy[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);
        sponge3d_apply_XY<<<dimGrid_spng_XY,dimBlock_spng_XY>>>(g, d_upy[g], fdm->nxpad, nyinterior, fdm->nzpad, nb);


        dim3 dimGrid_spng_ZY(ceil(nb/8.0f),ceil(fdm->nzpad/8.0f),ceil(nyinterior/8.0f));
        dim3 dimBlock_spng_ZY(8,8,8);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_umz[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_uoz[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_upz[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);

        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_umx[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_uox[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_upx[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);

        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_umy[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_uoy[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
        sponge3d_apply_ZY<<<dimGrid_spng_ZY,dimBlock_spng_ZY>>>(g, d_upy[g], fdm->nxpad, nyinterior, fdm->nzpad, nb, nx, spo);
      }


      cudaSetDevice(0);
      dim3 dimGrid_spng_XZ(ceil(fdm->nxpad/192.0f),1,fdm->nzpad);
      dim3 dimBlock_spng_XZ(192,1,1);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_umz[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_uoz[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_upz[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);

      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_umx[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_uox[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_upx[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);

      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_umy[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_uoy[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);
      sponge3d_apply_XZ_low<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_upy[0], fdm->nxpad, fdm->nzpad, nb, nylocal[0]);

      cudaSetDevice(ngpu-1);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_umz[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_uoz[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_upz[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);

      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_umx[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_uox[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_upx[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);

      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_umy[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_uoy[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);
      sponge3d_apply_XZ_high<<<dimGrid_spng_XZ,dimBlock_spng_XZ>>>(d_upy[ngpu-1], fdm->nxpad, nylocal[ngpu-1], fdm->nzpad, nb);

      sf_check_gpu_error("Boundary Condition Kernels");
    }


    /*------------------------------------------------------------*/
    /* exchange halo regions of d_uo arrays between GPUs          */
    /*------------------------------------------------------------*/
    if (ngpu > 1){

      // high halo region of d_uo arrays on GPU 0 to GPU 1
      cudaMemcpy(d_uox[1], d_uox[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_uoy[1], d_uoy[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_uoz[1], d_uoz[0] + (fdm->nxpad * fdm->nzpad * (nyinterior - 4)), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);

      // exchange halo regions of d_uo arrays between all internal GPUs
      for (int g = 1; g < ngpu-1; g++){
        // high halo region of d_uo arrays on GPU g to low halo region on GPU g+1
        cudaMemcpy(d_uox[g+1], d_uox[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_uoy[g+1], d_uoy[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_uoz[g+1], d_uoz[g] + (fdm->nxpad * fdm->nzpad * nyinterior), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);

        // low halo region of d_uo arrays on GPU g to high halo region on GPU g-1
        cudaMemcpy(d_uox[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_uox[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_uoy[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_uoy[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
        cudaMemcpy(d_uoz[g-1] + (fdm->nxpad * fdm->nzpad * (nylocal[g-1] - 4)), d_uoz[g] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      }

      // low halo region of d_uo arrays on GPU (ngpu-1) to GPU (ngpu-2)
      cudaMemcpy(d_uox[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_uox[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_uoy[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_uoy[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);
      cudaMemcpy(d_uoz[ngpu-2] + (fdm->nxpad * fdm->nzpad * (nylocal[ngpu-2] - 4)), d_uoz[ngpu-1] + (4 * fdm->nxpad * fdm->nzpad), 4 * fdm->nxpad * fdm->nzpad * sizeof(float), cudaMemcpyDefault);

    }

    gettimeofday(&stop, NULL);
    compute_elapsed += stop.tv_sec - start.tv_sec + (stop.tv_usec - start.tv_usec) * 1e-6;


    gettimeofday(&start, NULL);
    /*------------------------------------------------------------*/
    /* cut wavefield and save                     */
    /*    - Step #9                       */
    /*------------------------------------------------------------*/
    if(snap && total_iter%jsnap==0) {
      sf_warning("write wavefield files, total_iter: %d", total_iter);
      gather_from_gpu(fdm, h_ux, h_uy, h_uz, d_uox, d_uoy, d_uoz, uox, uoy, uoz, nyinterior, ngpu);

      // Write wavefield arrays to output file
      int size = fdm->nzpad * fdm->nxpad * fdm->nypad;
      cut3d(uoz,uc,fdm,az,ax,ay);
      sf_floatwrite(uc[0][0], size, Fwfl);

      cut3d(uox,uc,fdm,az,ax,ay);
      sf_floatwrite(uc[0][0],size, Fwfl);

      cut3d(uoy,uc,fdm,az,ax,ay);
      sf_floatwrite(uc[0][0],size, Fwfl);

    }

    /*------------------------------------------------------------*/
    /* extract receiver data                    */
    /*------------------------------------------------------------*/
    if(it%jdata==0) {
      if (interp){  // use interpolation
        for (int g = 0; g < ngpu; g++){
          cudaSetDevice(g);
          cudaMemset(d_dd[g], 0, nr*nc*sizeof(float));
          dim3 dimGrid_extract(MIN(nr,ceil(nr/1024.0f)), 1, 1);
          dim3 dimBlock_extract(MIN(nr, 1024), 1, 1);
          lint3d_extract_gpu<<<dimGrid_extract, dimBlock_extract>>>(g, d_dd[g], nr, fdm->nxpad, nyinterior, fdm->nzpad, d_uoz[g], d_uox[g], d_uoy[g], d_Rjz[g], d_Rjx[g], d_Rjy[g], d_Rw000[g], d_Rw001[g], d_Rw010[g], d_Rw011[g], d_Rw100[g], d_Rw101[g], d_Rw110[g], d_Rw111[g]);
        }
        sf_check_gpu_error("lint3d_extract kernel");
      }
      else {    // no interpolation
        for (int g = 0; g < ngpu; g++){
          cudaSetDevice(g);
          cudaMemset(d_dd[g], 0, nr*nc*sizeof(float));
          dim3 dimGrid_extract(MIN(nr,ceil(nr/1024.0f)), 1, 1);
          dim3 dimBlock_extract(MIN(nr, 1024), 1, 1);
          extract_gpu<<<dimGrid_extract, dimBlock_extract>>>(g, d_dd[g], nr, fdm->nxpad, nyinterior, fdm->nzpad, d_uoz[g], d_uox[g], d_uoy[g], d_Rjz[g], d_Rjx[g], d_Rjy[g]);
        }
        sf_check_gpu_error("extract_gpu kernel");

      }

      // copy GPU 0's receiver data into h_dd_combined
      cudaMemcpy(h_dd_combined, d_dd[0], nr * nc * sizeof(float), cudaMemcpyDefault);

      // add all other GPU's recever data to h_dd_combined
      for (int g = 1; g < ngpu; g++){
        cudaMemcpy(h_dd, d_dd[g], nr * nc * sizeof(float), cudaMemcpyDefault);
        for (int i = 0; i < nr * nc; i++){
          h_dd_combined[i] += h_dd[i];
        }
      }

      // write receiver data to output file
      sf_floatwrite(h_dd_combined, nr*nc, Fdat);
    }
    gettimeofday(&stop, NULL);
    io_elapse += stop.tv_sec - start.tv_sec + (stop.tv_usec - start.tv_usec) * 1e-6;

  } // END MAIN LOOP

  sf_warning("\ntotal iter: %d, time elapsed for computation  (not including output wavefield/data): %.4fs", total_iter, compute_elapsed);
  sf_warning("\ntotal iter: %d, time elapsed for input/output (not including main_loop computation): %.4fs", total_iter, io_elapse);

}
static void check_zx_dim(const fdm3d &fdm, int ngpu)
{
  // check that dimmeionsons are ok for FD kernels
  if ((fdm->nzpad - 8) % 24 != 0){
    sf_error("nz + 2*nb - 8 is not a multiple of 24");
  }
  if ((fdm->nxpad - 8) % 24 != 0){
    sf_error("nx + 2*nb - 8 is not a multiple of 24");
  }
  if ((fdm->nypad % ngpu) != 0){
    sf_error("You are using %d GPUs.\n(ny + 2*nb) must me a multiple of %d\nChange model dimensions or select a different number of GPUs", ngpu, ngpu);
  }
}
static void set_nylocal(const fdm3d &fdm, int *nylocal, int ngpu, int nyinterior)
{
  // all interior nodes need 8 additional ghost slices (4 on each side of the y axis)
  for (int g = 0; g < ngpu; g++){
    nylocal[g] = nyinterior + 8;
  }

  // exterior nodes only require 4 additional ghost slices
  if (ngpu >= 2){
    nylocal[0] = nyinterior + 4;
    nylocal[ngpu-1] = nyinterior + 4;
  }

  // if using 1 GPU, this GPU holds the entire domain
  if (ngpu == 1){
    nylocal[0] = fdm->nypad;
  }
}

static void make_axis(const fdm3d &fullfdm, modeling_t *m, int ngpu, sf_axis &az, sf_axis &ax, sf_axis &ay)
{
  /// make (nz+2nb-8) a multiple of 24
  int n1 = SF_MIN(24 * ceilf((m->n1 - 8) / 24.0) + 8 - 2 * m->nb, fullfdm->nz);
  int n2 = SF_MIN(24 * ceilf((m->n2 - 8) / 24.0) + 8 - 2 * m->nb, fullfdm->nx);

  /// n3 a multiple of ngpu
  int n3 = SF_MIN(ngpu * ceilf((m->n3 - 2 * m->nb) * 1.0 / ngpu), fullfdm->ny);
  //az = sf_maxa(m->n1 - 2 * m->nb, m->o1 + m->nb * m->d1, m->d1);
  //ax = sf_maxa(m->n2 - 2 * m->nb, m->o2 + m->nb * m->d2, m->d2);
  //ay = sf_maxa(m->n3 - 2 * m->nb, m->o3 + m->nb * m->d3, m->d3);

  //sf_warning("actual dimensions");
  az = sf_maxa(n1, m->o1 + m->nb * m->d1, m->d1); sf_raxa(az);
  ax = sf_maxa(n2, m->o2 + m->nb * m->d2, m->d2); sf_raxa(ax);
  ay = sf_maxa(n3, m->o3 + m->nb * m->d3, m->d3); sf_raxa(ay);
  sf_warning("========>");
}


/**
 * After calling this function, the following variables got updated:
 * h_umx, h_uox,  h_umy,  h_uoy,  h_umz,  h_uoz
 *
 * It also output the wavefield and data
 */
static void run(sf_file Fwfl, sf_file Fdat, const fdm3d &fdm,  pt3d *ss, pt3d *rr, sf_axis az, sf_axis ax, sf_axis ay, int nt, float dt, const float *h_ro, const float *h_c11, const float *h_c22, const float *h_c33, const float *h_c44, const float *h_c55, const float *h_c66, const float *h_c12, const float *h_c13, const float *h_c23, const float *h_vp, const float *h_vs, float ***h_umx, float ***h_uox,  float ***h_umy,  float ***h_uoy,  float ***h_umz,  float ***h_uoz, const float *h_ww, int ns, int nr, int ngpu, int jdata, int jsnap, int nbell, int nc, bool interp, bool ssou,  bool dabc, bool snap, bool fsrf, bool verb, int &total_iter, bool withq, float qp, float qs)
{

  /*------------------------------------------------------------*/
  // used for writing wavefield to file, only needed if snap=y
  float ***ux, ***uy, ***uz;
  float *h_ux, *h_uy, *h_uz;
  ux = uy = uz = NULL;
  h_ux = h_uy = h_uz = NULL;

  /* wavefield cut params */
  float     ***uc=NULL;

  float   idz,idx,idy;

  float *h_dd, *h_dd_combined, **d_dd;
  setup_output_array(h_dd, h_dd_combined, d_dd, ngpu, nr, nc);

  float **d_ww = copy_wavelet(h_ww, ns, nc, nt, ngpu);
  float **d_bell = setup_bell(nbell, ngpu);
  /*------------------------------------------------------------*/


  /*------------------------------------------------------------*/
  /* compute sub-domain dimmensions (domain decomposition) */
  int nyinterior = (fdm->nypad / ngpu);   // size of sub-domains in y-dimension EXCLUDING any ghost cells from adjacent GPUs
  int *nylocal = (int*)malloc(ngpu*sizeof(int));  // size of sub-domains in y-dimension INCLUDING any ghost cells from adjacent GPUs
  set_nylocal(fdm, nylocal, ngpu, nyinterior);
  check_zx_dim(fdm, ngpu);
  for (int i = 0; i < ngpu; i++) {
    sf_warning("nylocal[%d]: %d", i, nylocal[i]);
  }
  alloc_wlf(fdm, uz, ux, uy, h_uz, h_ux, h_uy, uc, nyinterior);
  float **d_Sw000,  **d_Sw001,  **d_Sw010,  **d_Sw011,  **d_Sw100,  **d_Sw101,  **d_Sw110,  **d_Sw111;
  float **d_Rw000,  **d_Rw001,  **d_Rw010,  **d_Rw011,  **d_Rw100,  **d_Rw101,  **d_Rw110,  **d_Rw111;
  int **d_Sjz,  **d_Sjx,  **d_Sjy;
  int **d_Rjz,  **d_Rjx,  **d_Rjy;

  /* calculate 3d linear interpolation coefficients for source/receiver locations and copy to each GPU*/
  setup_interp_cooef_source  (d_Sw000, d_Sw001, d_Sw010, d_Sw011, d_Sw100, d_Sw101, d_Sw110, d_Sw111, d_Sjz, d_Sjx, d_Sjy, fdm, ss, ns, ngpu);
  setup_interp_cooef_receiver(d_Rw000, d_Rw001, d_Rw010, d_Rw011, d_Rw100, d_Rw101, d_Rw110, d_Rw111, d_Rjz, d_Rjx, d_Rjy, fdm, rr, nr, ngpu);

  setup_fd_cooef(fdm, idz, idx, idy);
  float **d_ro ,  **d_c11,  **d_c22,  **d_c33,  **d_c44,  **d_c55,  **d_c66,  **d_c12,  **d_c13,  **d_c23, **d_vp, **d_vs;
  // TODO: rename h_ro and other similar to full_h_ro
  copy_den_vel_to_dev(fdm, d_ro , d_c11, d_c22, d_c33, d_c44, d_c55, d_c66, d_c12, d_c13, d_c23, d_vp, d_vs, h_ro, h_c11, h_c22, h_c33, h_c44, h_c55, h_c66, h_c12, h_c13, h_c23, h_vp, h_vs, nyinterior, ngpu);

  float spo = 0;
  float **d_bzl_s,  **d_bzh_s,  **d_bxl_s,  **d_bxh_s,  **d_byl_s,  **d_byh_s;
  setup_boundary(fdm, d_bzl_s, d_bzh_s, d_bxl_s, d_bxh_s, d_byl_s, d_byh_s, h_ro, h_c55, spo, nyinterior, ngpu, dt, dabc);

  float **d_umx,  **d_uox,  **d_upx,  **d_uax,  **d_utx,  **d_umy,  **d_uoy,  **d_upy,  **d_uay,  **d_uty,  **d_umz,  **d_uoz,  **d_upz,  **d_uaz,  **d_utz,  **d_tzz,  **d_txx,  **d_tyy,  **d_txy,  **d_tyz,  **d_tzx;
  init_wfd_array(fdm, h_ux, h_uy, h_uz, h_umx, h_uox, h_umy, h_uoy, h_umz, h_uoz, d_umx, d_uox, d_upx, d_uax, d_utx, d_umy, d_uoy, d_upy, d_uay, d_uty, d_umz, d_uoz, d_upz, d_uaz, d_utz, d_tzz, d_txx, d_tyy, d_txy, d_tyz, d_tzx, nylocal, ngpu, nyinterior);

  precompute(fdm, d_ro, dt, nyinterior, ngpu);


  /*------------------------------------------------------------*/
  /*
   *  MAIN LOOP
   */
  /*------------------------------------------------------------*/
  main_loop(Fwfl, Fdat, fdm, dt, d_umx, d_uox, d_upx, d_uax, d_utx, d_umy, d_uoy, d_upy, d_uay, d_uty, d_umz, d_uoz, d_upz, d_uaz, d_utz, d_tzz, d_txx, d_tyy, d_txy, d_tyz, d_tzx, d_c11, d_c22, d_c33, d_c44, d_c55, d_c66, d_c12, d_c13, d_c23, d_vp, d_vs, d_Sw000, d_Sw001, d_Sw010, d_Sw011, d_Sw100, d_Sw101, d_Sw110, d_Sw111, d_Sjz, d_Sjx, d_Sjy, d_Rw000, d_Rw001, d_Rw010, d_Rw011, d_Rw100, d_Rw101, d_Rw110, d_Rw111, d_Rjz, d_Rjx, d_Rjy, d_bell, d_ww, d_ro, d_bzl_s, d_bzh_s, d_bxl_s, d_bxh_s, d_byl_s, d_byh_s,  uz,  ux,  uy, h_uz, h_ux, h_uy, uc, h_dd, h_dd_combined, d_dd, az, ax, ay, nylocal, spo, idx, idy, idz, nt, jsnap, jdata, ngpu, nyinterior, ns, nr, nbell, nc, interp, snap, fsrf, ssou, dabc, verb, total_iter, withq, qp, qs);

  gather_from_gpu(fdm, h_ux, h_uy, h_uz, d_umx, d_umy, d_umz, h_umx, h_umy, h_umz, nyinterior, ngpu);
  gather_from_gpu(fdm, h_ux, h_uy, h_uz, d_uox, d_uoy, d_uoz, h_uox, h_uoy, h_uoz, nyinterior, ngpu);

  /*------------------------------------------------------------*/
  /* deallocate host arrays */

  free(h_dd); free(h_dd_combined);

  free(h_uz); free(h_ux); free(h_uy);
  free(**uc);  free(*uc);  free(uc);
  free(**uz); free(*uz); free(uz);
  free(**ux); free(*ux); free(ux);
  free(**uy); free(*uy); free(uy);


  /*------------------------------------------------------------*/
  /* deallocate GPU arrays */
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);

    cudaFree(d_ww[g]);
    cudaFree(d_dd[g]);
    cudaFree(d_bell[g]);

    cudaFree(d_ro[g]);
    cudaFree(d_c11[g]);
    cudaFree(d_c22[g]);
    cudaFree(d_c33[g]);
    cudaFree(d_c44[g]);
    cudaFree(d_c55[g]);
    cudaFree(d_c66[g]);
    cudaFree(d_c12[g]);
    cudaFree(d_c13[g]);
    cudaFree(d_c23[g]);
    cudaFree(d_vp[g]);
    cudaFree(d_vs[g]);

    if (dabc){
      cudaFree(d_bzl_s[g]);
      cudaFree(d_bzh_s[g]);
      cudaFree(d_bxl_s[g]);
      cudaFree(d_bxh_s[g]);
      if (g == 0) cudaFree(d_byl_s[0]);
      if (g == ngpu - 1) cudaFree(d_byh_s[ngpu-1]);
    }

    cudaFree(d_umx[g]); cudaFree(d_umy[g]); cudaFree(d_umz[g]);
    cudaFree(d_uox[g]); cudaFree(d_uoy[g]); cudaFree(d_uoz[g]);
    cudaFree(d_upx[g]); cudaFree(d_upy[g]); cudaFree(d_upz[g]);
    cudaFree(d_uax[g]); cudaFree(d_uay[g]); cudaFree(d_uaz[g]);

    cudaFree(d_tzz[g]); cudaFree(d_tyy[g]); cudaFree(d_txx[g]);
    cudaFree(d_txy[g]); cudaFree(d_tyz[g]); cudaFree(d_tzx[g]);

    cudaFree(d_Sjz[g]);
    cudaFree(d_Sjx[g]);
    cudaFree(d_Sjy[g]);
    cudaFree(d_Sw000[g]);
    cudaFree(d_Sw001[g]);
    cudaFree(d_Sw010[g]);
    cudaFree(d_Sw011[g]);
    cudaFree(d_Sw100[g]);
    cudaFree(d_Sw101[g]);
    cudaFree(d_Sw110[g]);
    cudaFree(d_Sw111[g]);

    cudaFree(d_Rjz[g]);
    cudaFree(d_Rjx[g]);
    cudaFree(d_Rjy[g]);
    if (interp){
      cudaFree(d_Rw000[g]);
      cudaFree(d_Rw001[g]);
      cudaFree(d_Rw010[g]);
      cudaFree(d_Rw011[g]);
      cudaFree(d_Rw100[g]);
      cudaFree(d_Rw101[g]);
      cudaFree(d_Rw110[g]);
      cudaFree(d_Rw111[g]);
    }
  }
}

static char *genWflName(int iblock, float qp, float qs) {
  static char fn[512];
  char *p = sf_getstring("wfl");
  strncpy(fn, p, strlen(p) + 1);
  p = strstr(fn, ".rsf");
  sprintf(p, "-qp%d-qs%d-b%d.rsf", (int)qp, (int)qs, iblock);
  sf_warning(fn);
  return fn;
}
// entry point
int main(int argc, char* argv[]) {

  bool verb,fsrf,snap,ssou,dabc,interp;
  int  jsnap,jdata;

  /* I/O files */
  sf_file Fwav=NULL; /* wavelet   */
  sf_file Fsou=NULL; /* sources   */
  sf_file Frec=NULL; /* receivers */
  sf_file Fccc=NULL; /* velocity  */
  sf_file Fden=NULL; /* density   */
  sf_file Fdat=NULL; /* data      */

  /* cube axes */
  sf_axis at,ax,ay,az;
  sf_axis as,ar;

  int     nt,nz,nx,ny,ns,nr,nb;
  float   dt;

  /* I/O arrays */
  pt3d   *ss=NULL;           /* sources   */
  pt3d   *rr=NULL;           /* receivers */


  /* Gaussian bell */
  int nbell;


  /* init RSF */
  sf_init(argc,argv);


  /*------------------------------------------------------------*/
  /* init GPU */
  int ngpu;
  if (! sf_getint("ngpu", &ngpu)) ngpu = 1; /* how many local GPUs to use */
  sf_warning("using %d GPUs", ngpu);

  /*------------------------------------------------------------*/
  /* execution flags */
  if(! sf_getbool("verb",&verb)) verb=false; /* verbosity flag */
  if(! sf_getbool("snap",&snap)) snap=true;
  if(! sf_getbool("free",&fsrf)) fsrf=false; /* free surface flag */
  if(! sf_getbool("ssou",&ssou)) ssou=false; /* stress source */
  if(! sf_getbool("dabc",&dabc)) dabc=false; /* absorbing BC */
  if(! sf_getbool("interp",&interp)) interp=true; /* perform linear interpolation on receiver data */

  /*------------------------------------------------------------*/
  /* I/O files */
  Fwav = sf_input ("in"); /* wavelet   */
  Fccc = sf_input ("ccc"); /* stiffness */
  Fden = sf_input ("den"); /* density   */
  Fsou = sf_input ("sou"); /* sources   */
  Frec = sf_input ("rec"); /* receivers */
  Fdat = sf_output("out"); /* data      */


  /*------------------------------------------------------------*/
  /* axes */
  at = sf_iaxa(Fwav,3); sf_setlabel(at,"t"); if(verb) sf_raxa(at); /* time */
  az = sf_iaxa(Fccc,1); sf_setlabel(az,"z"); if(verb) sf_raxa(az); /* depth */
  ax = sf_iaxa(Fccc,2); sf_setlabel(ax,"x"); if(verb) sf_raxa(ax); /* space x */
  ay = sf_iaxa(Fccc,3); sf_setlabel(ay,"y"); if(verb) sf_raxa(ay); /* space y */

  sf_axis asz, asx, asy;
  asz = sf_iaxa(Fsou, 2); asx = sf_iaxa(Fsou, 3); asy = sf_iaxa(Fsou, 4);
  as = sf_maxa(sf_n(asz) * sf_n(asx) * sf_n(asy), sf_d(asx), sf_o(asx));

  sf_axis arz, arx, ary;
  arz = sf_iaxa(Frec, 2); arx = sf_iaxa(Frec, 3); ary = sf_iaxa(Frec, 4);
  ar = sf_maxa(sf_n(arz) * sf_n(arx) * sf_n(ary), sf_d(arx), sf_o(arx));

  nt = sf_n(at); dt = sf_d(at);
  nz = sf_n(az);
  nx = sf_n(ax);
  ny = sf_n(ay);

  ns = sf_n(as);
  nr = sf_n(ar);


  /*------------------------------------------------------------*/
  /* other execution parameters */
  if(! sf_getint("nbell",&nbell)) nbell=5;  /* bell size */
  if(verb) sf_warning("nbell=%d",nbell);
  if(! sf_getint("jdata",&jdata)) jdata=1;  /* extract receiver data every jdata time steps */
  if(! sf_getint("jsnap",&jsnap)) jsnap=nt;  /* save wavefield every jsnap time steps */

  if( !sf_getint("nb",&nb) || nb<NOP) nb=NOP;

  /*------------------------------------------------------------*/
  /* 3D vector components */
  int nc=3;
  sf_axis ac=sf_maxa(nc  ,0,1);
  setup_output_data(Fdat, at, ar, ac, nt, jdata, dt);

  float *h_ww = init_wavelet(Fwav, ns, nc, nt);

  sf_axis full_az = sf_maxa(sf_n(az), sf_o(az), sf_d(az));
  sf_axis full_ax = sf_maxa(sf_n(ax), sf_o(ax), sf_d(ax));
  sf_axis full_ay = sf_maxa(sf_n(ay), sf_o(ay), sf_d(ay));
  fdm3d fullfdm=fdutil3d_init(verb,fsrf,full_az,full_ax,full_ay,nb,1);
  update_axis(fullfdm, full_az, full_ax, full_ay, verb);

  setup_src_rcv_cord(Fsou, Frec, ss, rr, ns, nr);

  float ***full_h_ro,  ***full_h_c11,  ***full_h_c22,  ***full_h_c33,  ***full_h_c44,  ***full_h_c55,  ***full_h_c66,  ***full_h_c12,  ***full_h_c13,  ***full_h_c23;
  read_density_velocity(Fden, Fccc, fullfdm, full_h_ro, full_h_c11, full_h_c22, full_h_c33, full_h_c44, full_h_c55, full_h_c66, full_h_c12, full_h_c13, full_h_c23, nz, nx, ny);

  sf_warning("begin conghui's code");
  int   timeblocks;
  float vmin;
  float vmax;
  float dmin;
  float dmax;
  float maxf; // maximum frequency
  float   error;
  float errorfact;
  float qfact;
  float downfact;
  float w0; // for velocity
  bool withq;
  int ntab = 10000;
  int lsinc = 8;
  float qp;
  float qs;

  if (!sf_getint("timeblocks", &timeblocks)) timeblocks = 40;
  if (!sf_getfloat("maxf", &maxf)) maxf = 80;
  if (!sf_getfloat("error", &error)) error = 20;
  if (!sf_getfloat("errorfact", &errorfact)) errorfact = 1.2;
  if (!sf_getfloat("downfact", &downfact)) downfact = 0.04;
  if (!sf_getfloat("w0", &w0)) w0 = 60;
  if (!sf_getbool("withq", &withq)) withq = false;
  if (!sf_getint("ntab", &ntab)) ntab = 1000;
  if (!sf_getint("lsinc", &lsinc)) lsinc = 8;
  if (!sf_getfloat("qp", &qp)) qp = 0;
  if (!sf_getfloat("qs", &qs)) qs = 0;

  if (fabs(qp - qs) > 1) {
    sf_error("we only support qp == qs");
  }
  qfact = qp;

  sf_file Fvelp = sf_input("vp"); // p wave velocity
  sf_file Fvels = sf_input("vs"); // s wave velocity
  float ***vp = sf_floatalloc3(nz, nx, ny);
  float ***vs = sf_floatalloc3(nz, nx, ny);
  sf_floatread(vp[0][0], nx*ny*nz, Fvelp);
  sf_floatread(vs[0][0], nx*ny*nz, Fvels);
  float ***full_h_vp = sf_floatalloc3(fullfdm->nzpad, fullfdm->nxpad, fullfdm->nypad);
  float ***full_h_vs = sf_floatalloc3(fullfdm->nzpad, fullfdm->nxpad, fullfdm->nypad);
  expand_cpu(vp[0][0],full_h_vp[0][0],fullfdm->nb, nx, fullfdm->nxpad, ny, fullfdm->nypad, nz, fullfdm->nzpad);
  expand_cpu(vs[0][0],full_h_vs[0][0],fullfdm->nb, nx, fullfdm->nxpad, ny, fullfdm->nypad, nz, fullfdm->nzpad);

  sf_seek(Fvelp, 0, SEEK_SET);
  sf_seek(Fvels, 0, SEEK_SET);
  vel_t *vv0 = clone_vel(vp, nz, nx, ny, sf_o(az), sf_o(ax), sf_o(ay), sf_d(az), sf_d(ax), sf_d(ay), w0, qfact);
  vmin_vmax_dmin_dmax(vv0, &vmin, &vmax, &dmin, &dmax);

  sf_warning("vmin: %f, vmax: %f, dmin: %f, dmax: %f", vmin, vmax, dmin, dmax);
  times_t *times = read_times();
  init_box(timeblocks, vmin, vmax, dmin, dmax, maxf, nb, error, errorfact, qfact, downfact, dt);
  box_t *domain = calc_shot_box(vv0, times, ss, rr, nr, nt, dt);

  sf_warning("make modeling");
  modeling_t initmodel = make_modeling(vv0);

  sf_warning("clone fdm");
  fdm3d oldfdm = clonefdm(fullfdm);

  // initialize host prev and current wavefield
  float ***h_umx, ***h_uox,  ***h_umy,  ***h_uoy,  ***h_umz,  ***h_uoz, ***h_vp, ***h_vs;
  sf_warning("init host prev and curr wavefields");
  init_host_umo(oldfdm, h_umx, h_uox,  h_umy,  h_uoy,  h_umz,  h_uoz, h_vp, h_vs);

  // initialize varying density and velocity
  float ***h_ro, ***h_c11, ***h_c22, ***h_c33, ***h_c44, ***h_c55, ***h_c66, ***h_c12, ***h_c13, ***h_c23;
  sf_warning("init host density and velocities");
  init_host_den_vel(fullfdm, full_h_ro, full_h_c11, full_h_c22, full_h_c33, full_h_c44, full_h_c55, full_h_c66, full_h_c12, full_h_c13, full_h_c23, full_h_vp, full_h_vs, h_ro, h_c11, h_c22, h_c33, h_c44, h_c55, h_c66, h_c12, h_c13, h_c23, h_vp, h_vs);

  if (withq) {
    sf_warning("Q approximation enabled, qp: %.1f, qs:%.1f", qp, qs);
  } else {
    sf_warning("No Q approximation");
  }
  int total_iter = 0;
  sf_warning("init cuda device ...");
  for (int g = 0; g < ngpu; g++){
    cudaSetDevice(g);
    cudaDeviceReset();
    cudaDeviceSetCacheConfig(cudaFuncCachePreferL1);
  }
  sf_warning("init cuda device finished");

  sf_warning("init sinc table");
  float *sinc_table = (float *)malloc(ntab * lsinc * sizeof *sinc_table);
  make_sinc_table(sinc_table, ntab, lsinc);

  for (int iblock = 0; iblock < domain->timeblocks; iblock++) {
    sf_warning("\n\nFORWARD BLOCK: %d", iblock);

    sf_axis curaz = sf_maxa(1,1,1); // dummy, update later
    sf_axis curax = sf_maxa(1,1,1); // dummy, update later
    sf_axis curay = sf_maxa(1,1,1); // dummy, update later
    modeling_t *cur = &domain->hyper[iblock];
    int curnt = cur->ntblock; sf_warning("curnt: %d", curnt);
    float curdt = cur->dt; sf_warning("dt: %f, cur->dt: %f", curdt, cur->dt);

    make_axis(fullfdm, cur, ngpu, curaz, curax, curay);

    fdm3d fdm=fdutil3d_init(verb,fsrf,curaz, curax, curay, nb,1);

    update_axis(fdm, curaz, curax, curay, verb);

    char *fn = genWflName(iblock, qp, qs);
    sf_file Fwfl = sf_output(fn);
    set_output_wfd_time_block(Fwfl, at, curaz, curax, curay, ac, curnt, total_iter, curdt, jsnap, verb);

    sf_warning("iterpolating density and velocity");
    interp_host_den_vel_patch_n(oldfdm, fdm, fullfdm, sinc_table, ntab, lsinc, full_h_ro, full_h_c11, full_h_c22, full_h_c33, full_h_c44, full_h_c55, full_h_c66, full_h_c12, full_h_c13, full_h_c23, full_h_vp, full_h_vs, h_ro, h_c11, h_c22, h_c33, h_c44, h_c55, h_c66, h_c12, h_c13, h_c23, h_vp, h_vs);

    sf_warning("iterpolating wavefields");
    interp_host_umo_patch_n(oldfdm, fdm, sinc_table, ntab, lsinc, h_umx, h_uox,  h_umy,  h_uoy,  h_umz,  h_uoz);

    run(Fwfl, Fdat, fdm, ss, rr, curaz, curax, curay, curnt, curdt, h_ro[0][0], h_c11[0][0], h_c22[0][0], h_c33[0][0], h_c44[0][0], h_c55[0][0], h_c66[0][0], h_c12[0][0], h_c13[0][0], h_c23[0][0], h_vp[0][0], h_vs[0][0], h_umx, h_uox, h_umy, h_uoy, h_umz, h_uoz, h_ww, ns, nr, ngpu, jdata, jsnap, nbell, nc, interp, ssou, dabc, snap, fsrf, verb, total_iter, withq, qp, qs);

    oldfdm = clonefdm(fdm);
  }

  /*------------------------------------------------------------*/
  /* deallocate host arrays */
  release_host_umo(h_umx, h_uox,  h_umy,  h_uoy,  h_umz,  h_uoz);
  release_host_den_vel(h_ro, h_c11, h_c22, h_c33, h_c44, h_c55, h_c66, h_c12, h_c13, h_c23);
  free(ss); free(rr);
  free(**full_h_ro); free(*full_h_ro); free(full_h_ro);
  free(**full_h_c11); free(**full_h_c22); free(**full_h_c33); free(**full_h_c44); free(**full_h_c55); free(**full_h_c66); free(**full_h_c12); free(**full_h_c13); free(**full_h_c23);
  free(*full_h_c11); free(*full_h_c22); free(*full_h_c33); free(*full_h_c44); free(*full_h_c55); free(*full_h_c66); free(*full_h_c12); free(*full_h_c13); free(*full_h_c23);
  free(full_h_c11); free(full_h_c22); free(full_h_c33); free(full_h_c44); free(full_h_c55); free(full_h_c66); free(full_h_c12); free(full_h_c13); free(full_h_c23);
  free(sinc_table);


  sf_close();
  exit(0);

}



