// Minimal libmpi_cxx.so.40 shim for torch 1.13 on systems with OpenMPI 5.
//
// torch 1.13 links against OpenMPI's C++ bindings. OpenMPI 5 dropped them, so
// `import torch` fails with:
//
//     libmpi_cxx.so.40: cannot open shared object file
//
// MPI is never initialised by PyTorch; the loader only needs these five
// symbols to resolve. The mangled names are:
//
//     _ZN3MPI4CommC1Ev          MPI::Comm::Comm()
//     _ZN3MPI4CommC2Ev          MPI::Comm::Comm()  (base-object variant)
//     _ZN3MPI8Datatype4FreeEv   MPI::Datatype::Free()
//     _ZN3MPI3Win4FreeEv        MPI::Win::Free()
//     ompi_mpi_cxx_op_intercept (data)
//     ompi_op_set_cxx_callback  (function)

#include <cstddef>

namespace MPI {

class Comm {
public:
    Comm();
};

class Datatype {
public:
    void Free();
};

class Win {
public:
    void Free();
};

}  // namespace MPI

MPI::Comm::Comm() {}
void MPI::Datatype::Free() {}
void MPI::Win::Free() {}

extern "C" {
int ompi_mpi_cxx_op_intercept = 0;
void ompi_op_set_cxx_callback() {}
}
