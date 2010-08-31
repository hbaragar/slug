BINDIR = /usr/local/bin
OPTFILES = find-git-files.opt find-git-repos.opt ometastore.opt

build:	.install_dependencies $(OFILES)
	@echo
	@echo "	make install	# to install in $(BINDIR)"
	@echo

.install_dependencies:
	./install_dependencies

install: slug $(OPTFILES)
	@cp slug `echo $(OPTFILES) | sed 's/.opt//g'` $(BINDIR)/

%.opt:
	omake
