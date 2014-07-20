ezlvm: A simple raw LVM storage adapter for xapi
================================================

Ezlvm allows virtual disks to be placed on LVM LVs on either existing
or specially-created volume groups. Ezlvm is designed to be
sysadmin-friendly by (i) allowing the volumes to be manipulated
out-of-band; (ii) by being written in a 'scripting' style; and (iii)
by using human-readable names for everything.

Roadmap
-------

This adapter will have the following features in v1:

1. Ezlvm interoperates with existing volume groups, as well as those it
   creates itself.

2. Ezlvm exposes devices raw so they can be accessed via blkback. This
   ensures a very low-latency datapath which is important for fast local
   devices (e.g. SSDs, PCIe flash)

3. Ezlvm volumes use human-readable, sysadmin-friendly, names rather than
   obscure UUIDs

4. Ezlvm uses LVM thin provisioning by default for fast volume creation
   and efficient use of space.

5. Ezlvm uses [ocamlscript](http://mjambon.com/ocamlscript.html) to combine
   the fast edit-run cycle of scripts with the static analysis provided
   via the OCaml typechecker.

This adarter will have the following features in v2:

1. Ezlvm supports snapshots from .qcow2/.vhd/.vmdk files stored on
   remote servers.
