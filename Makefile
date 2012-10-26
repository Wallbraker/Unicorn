########################################
# Find which compilers are installed.
#
DMD ?= $(shell which dmd)
HOST_UNAME := $(strip $(shell uname))
HOST_MACHINE := $(strip $(shell uname -m))
UNAME ?= $(HOST_UNAME)
MACHINE ?= $(strip $(shell uname -m))

ifeq ($(strip $(DMD)),)
  DMD := $(shell which gdmd)
  ifeq ($(strip $(DMD)),)
    DMD = gdmd
  endif
endif

########################################
# The find which platform rules to use.
#
ifeq ($(HOST_UNAME),Linux)
  OBJ_TYPE := o
else
ifeq ($(HOST_UNAME),Darwin)
  OBJ_TYPE := o
else
  OBJ_TYPE := obj
endif
endif


# gdmd's -g exports native D debugging info use
# that instead of emulated c ones that -gc gives us.
ifeq ($(notdir $(DMD)),gdmd)
	DEBUG_DFLAGS = -g -debug
else
ifeq ($(notdir $(DMD)),gdmd-v1)
	DEBUG_DFLAGS = -g -debug
else
	DEBUG_DFLAGS = -gc -debug
endif
endif


DFLAGS ?= $(DEBUG_DFLAGS)
LDFLAGS ?= $(DEBUG_DFLAGS)

TARGET = unicorn-bootstrap
DCOMP_FLAGS = -c -w -Isrc $(DFLAGS)
LINK_FLAGS = -quiet -L-ldl $(LDFLAGS)


ifeq ($(UNAME),Darwin)
  PLATFORM=mac
else
ifeq ($(UNAME),Linux)
  PLATFORM=linux
else
  PLATFORM=windows
  TARGET = unicorn-boostrap.exe

  # Change the link flags
  LINK_FLAGS = -quiet $(LDFLAGS)
endif
endif

OBJ_DIR=.obj/bootstrap-$(PLATFORM)-$(MACHINE)
DSRC = $(shell find src/uni -name "*.d") src/bootstrap.d
DOBJ = $(patsubst src/%.d, $(OBJ_DIR)/%.$(OBJ_TYPE), $(DSRC))
OBJ := $(DOBJ)


all: $(TARGET)
	@./$(TARGET)

$(OBJ_DIR)/%.$(OBJ_TYPE) : src/%.d Makefile
	@echo "  DMD    src/$*.d"
	@mkdir -p $(dir $@)
	@$(DMD) $(DCOMP_FLAGS) -of$@ src/$*.d

$(TARGET): $(OBJ) Makefile
	@echo "  LD     $@"
	@$(DMD) $(LINK_FLAGS) -of$@ $(OBJ)

clean:
	@rm -rf $(TARGET) .obj

debug: $(TARGET)
	@gdb ./$(TARGET)

.PHONY: all clean debug
