Copyright (C) 2010 Henry Baragar <henry.baragar@instantiated.ca>
          (C) 2008 Mauricio Fernandez <mfp@acm.org>
          (C) 2007 Jean-Francois Richard <jean-francois@richard.name>

slug -- snapshots using git
=================================
slug creates a Git repository of your $HOME directory.  That is it takes a 
snapshot/backup of it using Git.

Since slug builds upon the infrastructure offered by Git, it shares its main
strengths:
* speed: recovering your data is faster that cp -a...
* full revision history
* space-efficient data store, with file compression and textual/binary deltas
* efficient transport protocol to replicate the backup (faster than rsync)

slug uses Git's hook system to save and restore the information Git doesn't
track itself such as permissions, empty directories and optionally mtime
fields.

History
=======
slub mostly is "gibak" with some improvements.  I seem to have a lot of trouble
typing "gibak" and "gibak commit" (which just doesn't make sense to me).  So
I renamed it slug (following the meme use for name "git") and will changed the
"commit" command to "it".  A "slug away" command was added to push changes to 
a remote repository, either on the same machine or on a remote machine.


Dependencies
============
slug needs the following software at run-time:
* git (tested with git version 1.5.4.2, might work with earlier versions)
* rsync >= 2.6.4 (released on 30 March 2005), used to manage nested git
  repositories (submodules)
* common un*x userland: bash, basename, pwd, hostname, cut, grep,
  egrep, date...

It needs the following software to compile:
* ocaml (tested with version 3.10.1 and 3.10.2)
* omake 
* ocaml-fileutils
* Findlib

To install dependencies on Mac:
* sudo port install git-core rsync caml-findlib omake
* There is no port for ocaml-fileutils; you'll have to build it from source at http://le-gall.net/sylvain+violaine/download/ocaml-fileutils-latest.tar.gz

Installation
============

(1) Verify the compilation parameters in OMakefile. The defaults should work
in most cases, but you might need to change a couple variables:
* include paths for the caml headers, required in some OCaml setups
* support for extended attributes. Tested on Linux and OSX.

(2) run

 $ omake

(3) copy the following executables to a directory in your path:

  find-git-files
  find-git-repos
  slug
  ometastore

Usage
=====

Run slug without any options to get a help message.

The normal workflow is:

 $ slug init         # run once to initialize the backup system
 $ vim .gitignore    # edit to make sure you don't import unwanted files
                     # edit .gitignore files in other subdirectories
                     # you can get a list of the files which will be saved
                     # with  find-git-files  or  slug ls-new-files
 $ slug it           # the first slug-it will be fairly slow, but the following
                     # ones will be very fast

.... later ....

 $ slug it

The backup will be placed in $HOME/.git. "Nested Git repositories" will be
rsync'ed to $HOME/.git/git-repositories and they will be registered as
submodules in the main Git repository (run  git help submodule  for more
information on submodules). You might want to use a cronjob to save snapshots
of the repositories in $HOME/.git/git-repositories 

After you slug init, $HOME becomes a git repository, so you can use normal git
commands. If you use "slug it", however, new files will automatically be
added to the repository if they are not ignored (as indicated in your
.gitignore files), so you'll normally prefer it to "git commit".


Extended Usage
==============

The major advantage of using slug over gibak is ability to easily back up the
repository to another location, probably on another machine.

The extended workflow is:

 $ slug it           # From the normal workflow
 $ slug away /abosulute/path
                     # where /absolute/path is where a new bare git repository
                     # is to be created (i.e. a copy of $HOME/.git)
                     # NB. the first slug-it will be fairly slow, but the
                     # following ones will be very fast

.... later ....

 $ slug it
 $ slug away         # pushes the repository changes to the /absolute/path

.... even later ....

 $ slug it away      # same as "slug it; slug away"

Note that the "/abosolute/path" can be replaced with a scp target (e.g.
user@remote.host:path) to place the "away" repository on a remote machine.


Advanced Usage
==============

Its possible, if you are careful, to use slug to keep to keep synchronized
two home directories on two different machines.  This section explains how.

First, you need to set things up as follows (assuming you have a desktop
and a laptop):

 1. "slug init" on the desktop
 2. "slug it" on the desktop
 3. copy files from the laptop that are missing onto the desktop
 4. "slug it" on the desktop
 5. "slug away /disk2/henry.slug"
 6. back up and remove all files from the home directory (e.g. /home/henry) on the laptop
 7. "slug clone henry@desktop/disk2/henry.slug /home/henry" on the laptop

Now the two home directories should be synchronized. And yes, you have and need all
three repositories.

When you start working on either the desktop or the laptop, the advanced
workflow is:

 $ slug away          # to ensure the local home directory is up to date
                      # with the <away-repo>

.... after the work is done ....

 $ slug it away       # to ensure that the <away-repo> is updated

If you forget to "slug it away" after working on one machine and after working on
the other machine (or have to work on both machines simultaneously), you still can use 
the advanced workflow to resynchronize your home directories.  If Git can resolve 
the differences, than the files will automatically be merged.  If not, then you will
have to follow the Git procedures to resolve the conflicts and use Git to update
your repository, at which point you can use "slug away" again.



Known Bugs
==========

* ometastore gets confused trying to do chown and utime on symlinks.  It spits a harmless error
  out, but this should be cleaned up.


License
=======
The slug script is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 2 of the License, or (at your option) any
later version.

The ometastore, find-git-files and find-git-repos programs are distributed
under the terms of the GNU Library General Public License version 2.1 (found
in LICENSE). All .ml source files are referred as "the Library" hereunder.

As a special exception to the GNU Lesser General Public License, you may link,
statically or dynamically, a "work that uses the Library" with a publicly
distributed version of the Library to produce an executable file containing
portions of the Library, and distribute that executable file under terms of
your choice, without any of the additional requirements listed in clause 6 of
the GNU Lesser General Public License.  By "a publicly distributed version of
the Library", we mean either the unmodified Library as distributed by the
author, or a modified version of the Library that is distributed under the
conditions defined in clause 2 of the GNU Lesser General Public License.  This
exception does not however invalidate any other reasons why the executable
file might be covered by the GNU Lesser General Public License.

