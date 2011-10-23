// **************************************************************************
//                               cg_cmm_msm.cu
//                             -------------------
//                           W. Michael Brown (ORNL)
//
//  Device code for acceleration of the cg/cmm/msm pair style
//
// __________________________________________________________________________
//    This file is part of the LAMMPS Accelerator Library (LAMMPS_AL)
// __________________________________________________________________________
//
//    begin                : 
//    email                : brownw@ornl.gov
// ***************************************************************************/

#ifdef NV_KERNEL
#include "lal_aux_fun1.h"
texture<float4> pos_tex;
texture<float> q_tex;
#ifndef _DOUBLE_DOUBLE
ucl_inline float4 fetch_pos(const int& i, const float4 *pos) 
  { return tex1Dfetch(pos_tex, i); }
ucl_inline float fetch_q(const int& i, const float *q) 
  { return tex1Dfetch(q_tex, i); }
#endif
#endif

__kernel void kernel_pair(__global numtyp4 *x_, __global numtyp4 *lj1,
                          __global numtyp4* lj3, const int lj_types, 
                          __global numtyp *sp_lj_in, __global int *dev_nbor, 
                          __global int *dev_packed, __global acctyp4 *ans,
                          __global acctyp *engv, const int eflag,
                          const int vflag, const int inum,
                          const int nbor_pitch, __global numtyp *q_,
                          const numtyp cut_coulsq, const numtyp qqrd2e,
                          const int smooth, const int t_per_atom) {
  int tid, ii, offset;
  atom_info(t_per_atom,ii,tid,offset);

  __local numtyp sp_lj[8];
  sp_lj[0]=sp_lj_in[0];
  sp_lj[1]=sp_lj_in[1];
  sp_lj[2]=sp_lj_in[2];
  sp_lj[3]=sp_lj_in[3];
  sp_lj[4]=sp_lj_in[4];
  sp_lj[5]=sp_lj_in[5];
  sp_lj[6]=sp_lj_in[6];
  sp_lj[7]=sp_lj_in[7];
  __local numtyp _ia;
  __local numtyp _ia2;
  __local numtyp _ia3;

  acctyp energy=(acctyp)0;
  acctyp e_coul=(acctyp)0;
  acctyp4 f;
  f.x=(acctyp)0; f.y=(acctyp)0; f.z=(acctyp)0;
  acctyp virial[6];
  for (int i=0; i<6; i++)
    virial[i]=(acctyp)0;
  
  if (ii<inum) {
    _ia=(numtyp)-1.0/sqrt(cut_coulsq);
    _ia2=(numtyp)-1.0/cut_coulsq;
    _ia3=_ia2*_ia;
    
    __global int *nbor, *list_end;
    int i, numj, n_stride;
    nbor_info(dev_nbor,dev_packed,nbor_pitch,t_per_atom,ii,offset,i,numj,
              n_stride,list_end,nbor);
  
    numtyp4 ix=fetch_pos(i,x_); //x_[i];
    numtyp qtmp=fetch_q(i,q_);
    int itype=ix.w;

    for ( ; nbor<list_end; nbor+=n_stride) {
      int j=*nbor;

      numtyp factor_lj, factor_coul;
      factor_lj = sp_lj[sbmask(j)];
      factor_coul = (numtyp)1.0-sp_lj[sbmask(j)+4];
      j &= NEIGHMASK;

      numtyp4 jx=fetch_pos(j,x_); //x_[j];
      int jtype=jx.w;

      // Compute r12
      numtyp delx = ix.x-jx.x;
      numtyp dely = ix.y-jx.y;
      numtyp delz = ix.z-jx.z;
      numtyp rsq = delx*delx+dely*dely+delz*delz;

      int mtype=itype*lj_types+jtype;
      if (rsq<lj1[mtype].x) {
        numtyp forcecoul, force_lj, force, inv1, inv2, prefactor;
        numtyp r2inv=(numtyp)1.0/rsq;

        if (rsq < lj1[mtype].y) {
          if (lj3[mtype].x == (numtyp)2) {
            inv1=r2inv*r2inv;
            inv2=inv1*inv1;
          } else if (lj3[mtype].x == (numtyp)1) {
            inv2=r2inv*sqrt(r2inv);
            inv1=inv2*inv2;
          } else {
            inv1=r2inv*r2inv*r2inv;
            inv2=inv1;
          }
          force_lj = factor_lj*inv1*(lj1[mtype].z*inv2-lj1[mtype].w);
        } else
          force_lj = (numtyp)0.0;

        numtyp ir, r2_ia2, r4_ia4, r6_ia6;
        if (rsq < cut_coulsq) {
          ir = (numtyp)1.0/sqrt(rsq);
          prefactor = qqrd2e*qtmp*fetch_q(j,q_);
          r2_ia2 = rsq*_ia2;
          r4_ia4 = r2_ia2*r2_ia2;
          if (smooth==0)
            forcecoul = prefactor*(_ia3*((numtyp)-4.375+(numtyp)5.25*r2_ia2-
                                        (numtyp)1.875*r4_ia4)-ir/rsq-
                                        factor_coul*ir);
          else {
            r6_ia6 = r2_ia2*r4_ia4;
            forcecoul = prefactor*(_ia3*((numtyp)-6.5625+(numtyp)11.8125*
                                         r2_ia2-(numtyp)8.4375*r4_ia4+
                                         (numtyp)2.1875*r6_ia6)-ir/rsq-
                                         factor_coul*ir);
          }
        } else
          forcecoul = (numtyp)0.0;

        force = forcecoul + force_lj * r2inv;

        f.x+=delx*force;
        f.y+=dely*force;
        f.z+=delz*force;

        if (eflag>0) {
          if (rsq < cut_coulsq)
            if (smooth==0)
              e_coul += prefactor*(ir+_ia*((numtyp)2.1875-(numtyp)2.1875*r2_ia2+
                                           (numtyp)1.3125*r4_ia4-
                                           (numtyp)0.3125*r4_ia4*r2_ia2)-
                                           factor_coul*ir);
            else
              e_coul += prefactor*(ir+_ia*((numtyp)2.4609375-(numtyp)3.28125*
                                           r2_ia2+(numtyp)2.953125*r4_ia4-
                                           (numtyp)1.40625*r6_ia6+
                                           (numtyp)0.2734375*r4_ia4*r4_ia4));
              
          if (rsq < lj1[mtype].y) {
            energy += factor_lj*inv1*(lj3[mtype].y*inv2-lj3[mtype].z)-
                      lj3[mtype].w;
          } 
        }
        if (vflag>0) {
          virial[0] += delx*delx*force;
          virial[1] += dely*dely*force;
          virial[2] += delz*delz*force;
          virial[3] += delx*dely*force;
          virial[4] += delx*delz*force;
          virial[5] += dely*delz*force;
        }
      }

    } // for nbor
    store_answers_q(f,energy,e_coul,virial,ii,inum,tid,t_per_atom,offset,eflag,
                    vflag,ans,engv);
  } // if ii
}

__kernel void kernel_pair_fast(__global numtyp4 *x_, __global numtyp4 *lj1_in,
                               __global numtyp4* lj3_in, 
                               __global numtyp* sp_lj_in,
                               __global int *dev_nbor, __global int *dev_packed,
                               __global acctyp4 *ans, __global acctyp *engv, 
                               const int eflag, const int vflag, const int inum, 
                               const int nbor_pitch, __global numtyp *q_,
                               const numtyp cut_coulsq, const numtyp qqrd2e,
                               const int smooth, const int t_per_atom) {
  int tid, ii, offset;
  atom_info(t_per_atom,ii,tid,offset);

  __local numtyp4 lj1[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp4 lj3[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp sp_lj[8];
  if (tid<8)
    sp_lj[tid]=sp_lj_in[tid];
  if (tid<MAX_SHARED_TYPES*MAX_SHARED_TYPES) {
    lj1[tid]=lj1_in[tid];
    lj3[tid]=lj3_in[tid];
  }
  
  acctyp energy=(acctyp)0;
  acctyp e_coul=(acctyp)0;
  acctyp4 f;
  f.x=(acctyp)0; f.y=(acctyp)0; f.z=(acctyp)0;
  acctyp virial[6];
  for (int i=0; i<6; i++)
    virial[i]=(acctyp)0;
  
  __local numtyp _ia;
  __local numtyp _ia2;
  __local numtyp _ia3;
  _ia=(numtyp)-1.0/sqrt(cut_coulsq);
  _ia2=(numtyp)1.0/cut_coulsq;
  _ia3=_ia2*_ia;
  __syncthreads();
  
  if (ii<inum) {
    __global int *nbor, *list_end;
    int i, numj, n_stride;
    nbor_info(dev_nbor,dev_packed,nbor_pitch,t_per_atom,ii,offset,i,numj,
              n_stride,list_end,nbor);
  
    numtyp4 ix=fetch_pos(i,x_); //x_[i];
    numtyp qtmp=fetch_q(i,q_);
    int iw=ix.w;
    int itype=mul24((int)MAX_SHARED_TYPES,iw);

    for ( ; nbor<list_end; nbor+=n_stride) {
      int j=*nbor;

      numtyp factor_lj, factor_coul;
      factor_lj = sp_lj[sbmask(j)];
      factor_coul = (numtyp)1.0-sp_lj[sbmask(j)+4];
      j &= NEIGHMASK;

      numtyp4 jx=fetch_pos(j,x_); //x_[j];
      int mtype=itype+jx.w;

      // Compute r12
      numtyp delx = ix.x-jx.x;
      numtyp dely = ix.y-jx.y;
      numtyp delz = ix.z-jx.z;
      numtyp rsq = delx*delx+dely*dely+delz*delz;

      if (rsq<lj1[mtype].x) {
        numtyp forcecoul, force_lj, force, inv1, inv2, prefactor;
        numtyp r2inv=(numtyp)1.0/rsq;

        if (rsq < lj1[mtype].y) {
          if (lj3[mtype].x == (numtyp)2) {
            inv1=r2inv*r2inv;
            inv2=inv1*inv1;
          } else if (lj3[mtype].x == (numtyp)1) {
            inv2=r2inv*sqrt(r2inv);
            inv1=inv2*inv2;
          } else {
            inv1=r2inv*r2inv*r2inv;
            inv2=inv1;
          }
          force_lj = factor_lj*inv1*(lj1[mtype].z*inv2-lj1[mtype].w);
        } else
          force_lj = (numtyp)0.0;

        numtyp ir, r2_ia2, r4_ia4, r6_ia6;
        if (rsq < cut_coulsq) {
          ir = (numtyp)1.0/sqrt(rsq);
          prefactor = qqrd2e*qtmp*fetch_q(j,q_);
          r2_ia2 = rsq*_ia2;
          r4_ia4 = r2_ia2*r2_ia2;
          if (smooth==0)
            forcecoul = prefactor*(_ia3*((numtyp)-4.375+(numtyp)5.25*r2_ia2-
                                        (numtyp)1.875*r4_ia4)-ir/rsq-
                                        factor_coul*ir);
          else {
            r6_ia6 = r2_ia2*r4_ia4;
            forcecoul = prefactor*(_ia3*((numtyp)-6.5625+(numtyp)11.8125*
                                         r2_ia2-(numtyp)8.4375*r4_ia4+
                                         (numtyp)2.1875*r6_ia6)-ir/rsq-
                                         factor_coul*ir);
          }
        } else
          forcecoul = (numtyp)0.0;

        force = forcecoul + force_lj * r2inv;

        f.x+=delx*force;
        f.y+=dely*force;
        f.z+=delz*force;

        if (eflag>0) {
          if (rsq < cut_coulsq)
            if (smooth==0)
              e_coul += prefactor*(ir+_ia*((numtyp)2.1875-(numtyp)2.1875*r2_ia2+
                                           (numtyp)1.3125*r4_ia4-
                                           (numtyp)0.3125*r4_ia4*r2_ia2)-
                                           factor_coul*ir);
            else
              e_coul += prefactor*(ir+_ia*((numtyp)2.4609375-(numtyp)3.28125*
                                           r2_ia2+(numtyp)2.953125*r4_ia4-
                                           (numtyp)1.40625*r6_ia6+
                                           (numtyp)0.2734375*r4_ia4*r4_ia4));
          if (rsq < lj1[mtype].y) {
            energy += factor_lj*inv1*(lj3[mtype].y*inv2-lj3[mtype].z)-
                      lj3[mtype].w;
          } 
        }
        if (vflag>0) {
          virial[0] += delx*delx*force;
          virial[1] += dely*dely*force;
          virial[2] += delz*delz*force;
          virial[3] += delx*dely*force;
          virial[4] += delx*delz*force;
          virial[5] += dely*delz*force;
        }
      }

    } // for nbor
    store_answers_q(f,energy,e_coul,virial,ii,inum,tid,t_per_atom,offset,eflag,
                    vflag,ans,engv);
  } // if ii
}

