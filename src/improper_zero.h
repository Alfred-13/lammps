/* -*- c++ -*- ----------------------------------------------------------
   LAMMPS - Large-scale Atomic/Molecular Massively Parallel Simulator
   http://lammps.sandia.gov, Sandia National Laboratories
   Steve Plimpton, sjplimp@sandia.gov

   Copyright (2003) Sandia Corporation.  Under the terms of Contract
   DE-AC04-94AL85000 with Sandia Corporation, the U.S. Government retains
   certain rights in this software.  This software is distributed under
   the GNU General Public License.

   See the README file in the top-level LAMMPS directory.
------------------------------------------------------------------------- */

#ifdef IMPROPER_CLASS

ImproperStyle(zero,ImproperZero)

#else

#ifndef LMP_IMPROPER_ZERO_H
#define LMP_IMPROPER_ZERO_H

#include <stdio.h>
#include "improper.h"

namespace LAMMPS_NS {

class ImproperZero : public Improper {
 public:
  ImproperZero(class LAMMPS *);
  virtual ~ImproperZero();
  virtual void compute(int, int);
  virtual void coeff(int, char **);
  virtual void settings(int, char **);

  void write_restart(FILE *);
  void read_restart(FILE *);
  void write_data(FILE *);

 protected:
  int check_coeffs;

  virtual void allocate();
};

}

#endif
#endif

/* ERROR/WARNING messages:

E: Incorrect args for improper coefficients

Self-explanatory.  Check the input script or data file.

*/
