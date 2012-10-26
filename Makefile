
DCOMP=dmd
DCOMP_FLAGS=-Isrc $(DFLAGS)

OFILES = \
	bin/bootstrap/bootstrap.obj \
	bin/bootstrap/uni/core/def.obj \
	bin/bootstrap/uni/core/solver.obj \
	bin/bootstrap/uni/core/target.obj \
	bin/bootstrap/uni/lang/d.obj \
	bin/bootstrap/uni/license.obj \
	bin/bootstrap/uni/util/cmd.obj \
	bin/bootstrap/uni/util/env.obj \
	bin/bootstrap/uni/util/path.obj




all: unicorn-bootstrap.exe
	@./unicorn-bootstrap.exe

clean:
	@rmdir /s /q bin
	@rmdir /s /q .obj

unicorn-bootstrap.exe: $(OFILES)
	$(DCOMP) -ofunicorn-bootstrap.exe $(OFILES)

bin/bootstrap/bootstrap.obj: src/bootstrap.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/bootstrap.d -ofbin/bootstrap/bootstrap.obj

bin/bootstrap/uni/core/def.obj: src/uni/core/def.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/core/def.d -ofbin/bootstrap/uni/core/def.obj

bin/bootstrap/uni/core/solver.obj: src/uni/core/solver.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/core/solver.d -ofbin/bootstrap/uni/core/solver.obj

bin/bootstrap/uni/core/target.obj: src/uni/core/target.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/core/target.d -ofbin/bootstrap/uni/core/target.obj

bin/bootstrap/uni/lang/d.obj: src/uni/lang/d.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/lang/d.d -ofbin/bootstrap/uni/lang/d.obj

bin/bootstrap/uni/license.obj: src/uni/license.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/license.d -ofbin/bootstrap/uni/license.obj

bin/bootstrap/uni/util/cmd.obj: src/uni/util/cmd.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/util/cmd.d -ofbin/bootstrap/uni/util/cmd.obj

bin/bootstrap/uni/util/env.obj: src/uni/util/env.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/util/env.d -ofbin/bootstrap/uni/util/env.obj

bin/bootstrap/uni/util/path.obj: src/uni/util/path.d
	$(DCOMP) $(DCOMP_FLAGS) -c src/uni/util/path.d -ofbin/bootstrap/uni/util/path.obj


.PHONY: all
