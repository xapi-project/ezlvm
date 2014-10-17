ezlvm: A simple raw LVM storage adapter for xapi
================================================

Ezlvm allows virtual disks to be placed on LVM LVs on either existing
or specially-created volume groups. Ezlvm is designed to be
sysadmin-friendly by (i) allowing the volumes to be manipulated
out-of-band; (ii) by being written in a 'scripting' style; and (iii)
by using human-readable names for everything.

Roadmap
-------

This adapter will have the following features in v1: (an [x] means the
feature is already implemented)

- [ ] Ezlvm interoperates with existing volume groups, as well as those it
      creates itself.

- [x] Ezlvm exposes devices raw so they can be accessed via blkback. This
      ensures a very low-latency datapath which is important for fast local
      devices (e.g. SSDs, PCIe flash)

- [x] Ezlvm volumes use human-readable, sysadmin-friendly, names rather than
      obscure UUIDs

- [ ] Ezlvm uses LVM thin provisioning by default for fast volume creation
      and efficient use of space.

- [x] Ezlvm uses [ocamlscript](http://mjambon.com/ocamlscript.html) to combine
      the fast edit-run cycle of scripts with the static analysis provided
      via the OCaml typechecker.

