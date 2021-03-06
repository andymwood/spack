%=============================================================================
% Generate
%=============================================================================

%-----------------------------------------------------------------------------
% Version semantics
%-----------------------------------------------------------------------------

% versions are declared w/priority -- declared with priority implies declared
version_declared(Package, Version) :- version_declared(Package, Version, _).

% If something is a package, it has only one version and that must be a
% declared version.
1 { version(Package, Version) : version_declared(Package, Version) } 1
 :- node(Package).

version_weight(Package, Weight)
 :- version(Package, Version), version_declared(Package, Version, Weight),
    not preferred_version_declared(Package, Version, _).

version_weight(Package, Weight)
  :- version(Package, Version), preferred_version_declared(Package, Version, Weight).

% version_satisfies implies that exactly one of the satisfying versions
% is the package's version, and vice versa.
1 { version(Package, Version) : version_satisfies(Package, Constraint, Version) } 1
  :- version_satisfies(Package, Constraint).
version_satisfies(Package, Constraint)
  :- version(Package, Version), version_satisfies(Package, Constraint, Version).

#defined preferred_version_declared/3.
#defined version_satisfies/3.

%-----------------------------------------------------------------------------
% Dependency semantics
%-----------------------------------------------------------------------------
% Dependencies of any type imply that one package "depends on" another
depends_on(Package, Dependency) :- depends_on(Package, Dependency, _).

% declared dependencies are real if they're not virtual AND
% the package is not an external
depends_on(Package, Dependency, Type)
 :- declared_dependency(Package, Dependency, Type),
    node(Package),
    not virtual(Dependency),
    not external(Package).

% if you declare a dependency on a virtual AND the package is not an external,
% you depend on one of its providers
1 {
  depends_on(Package, Provider, Type)
  : provides_virtual(Provider, Virtual)
} 1
 :- declared_dependency(Package, Virtual, Type),
    virtual(Virtual),
    not external(Package),
    node(Package).

% if a virtual was required by some root spec, one provider is in the DAG
1 { node(Package) : provides_virtual(Package, Virtual) } 1
 :- virtual_node(Virtual).

% a node that provides a virtual is a provider
provider(Package, Virtual)
  :- node(Package), provides_virtual(Package, Virtual).

% for any virtual, there can be at most one provider in the DAG
0 { provider(Package, Virtual) :
    node(Package), provides_virtual(Package, Virtual) } 1 :- virtual(Virtual).

% give dependents the virtuals they want
provider_weight(Dependency, 0)
 :- virtual(Virtual), depends_on(Package, Dependency),
    provider(Dependency, Virtual),
    external(Dependency).

provider_weight(Dependency, Weight)
 :- virtual(Virtual), depends_on(Package, Dependency),
    provider(Dependency, Virtual),
    pkg_provider_preference(Package, Virtual, Dependency, Weight),
    not external(Dependency).

provider_weight(Dependency, Weight)
 :- virtual(Virtual), depends_on(Package, Dependency),
    provider(Dependency, Virtual),
    not pkg_provider_preference(Package, Virtual, Dependency, _),
    not external(Dependency),
    default_provider_preference(Virtual, Dependency, Weight).

% if there's no preference for something, it costs 100 to discourage its
% use with minimization
provider_weight(Dependency, 100)
 :- virtual(Virtual),
    provider(Dependency, Virtual),
    depends_on(Package, Dependency),
    not external(Dependency),
    not pkg_provider_preference(Package, Virtual, Dependency, _),
    not default_provider_preference(Virtual, Dependency, _).

% Do the same for virtual roots
provider_weight(Package, Weight)
 :- virtual_root(Virtual),
    provider(Package, Virtual),
    default_provider_preference(Virtual, Package, Weight).

provider_weight(Package, 100)
 :- virtual_root(Virtual),
    provider(Package, Virtual),
    not default_provider_preference(Virtual, Package, _).

% all nodes must be reachable from some root
node(Package) :- root(Package).

1 { root(Package) : provides_virtual(Package, Virtual) } 1
  :- virtual_root(Virtual).

needed(Package) :- root(Package).
needed(Dependency) :- needed(Package), depends_on(Package, Dependency).
:- node(Package), not needed(Package).

% real dependencies imply new nodes.
node(Dependency) :- node(Package), depends_on(Package, Dependency).

% Avoid cycles in the DAG
path(Parent, Child) :- depends_on(Parent, Child).
path(Parent, Descendant) :- path(Parent, A), depends_on(A, Descendant).
:- path(A, B), path(B, A).

% do not warn if generated program contains none of these.
#defined depends_on/3.
#defined declared_dependency/3.
#defined virtual/1.
#defined virtual_node/1.
#defined virtual_root/1.
#defined provides_virtual/2.
#defined external/1.
#defined external_spec/2.
#defined external_version_declared/4.
#defined external_only/1.
#defined pkg_provider_preference/4.
#defined default_provider_preference/3.
#defined root/1.

%-----------------------------------------------------------------------------
% External semantics
%-----------------------------------------------------------------------------

% if an external version is declared, it is also declared globally
version_declared(Package, Version, Weight) :- external_version_declared(Package, Version, Weight, _).

% if a package is external its version must be one of the external versions
1 { version(Package, Version): external_version_declared(Package, Version, _, _) } 1 :- external(Package).

% if a package is not buildable (external_only), only externals are allowed
external(Package) :- external_only(Package), node(Package).

% a package is a real_node if it is not external
real_node(Package) :- node(Package), not external(Package).

% if an external version is selected, the package is external and
% we are using the corresponding spec
external(Package) :-
    version(Package, Version), version_weight(Package, Weight),
    external_version_declared(Package, Version, Weight, ID).

external_spec(Package, ID) :-
    version(Package, Version), version_weight(Package, Weight),
    external_version_declared(Package, Version, Weight, ID).

%-----------------------------------------------------------------------------
% Variant semantics
%-----------------------------------------------------------------------------
% one variant value for single-valued variants.
1 {
  variant_value(Package, Variant, Value)
  : variant_possible_value(Package, Variant, Value)
} 1
 :- node(Package),
    variant(Package, Variant),
    variant_single_value(Package, Variant).

% at least one variant value for multi-valued variants.
1 {
 variant_value(Package, Variant, Value)
 : variant_possible_value(Package, Variant, Value)
}
 :- node(Package),
    variant(Package, Variant),
    not variant_single_value(Package, Variant).

% if a variant is set to anything, it is considered 'set'.
variant_set(Package, Variant) :- variant_set(Package, Variant, _).

% A variant cannot have a value that is not also a possible value
:- variant_value(Package, Variant, Value), not variant_possible_value(Package, Variant, Value).

% variant_set is an explicitly set variant value. If it's not 'set',
% we revert to the default value. If it is set, we force the set value
variant_value(Package, Variant, Value)
 :- node(Package),
    variant(Package, Variant),
    variant_set(Package, Variant, Value).

% prefer default values.
variant_not_default(Package, Variant, Value, 1)
 :- variant_value(Package, Variant, Value),
    not variant_default_value(Package, Variant, Value),
    not variant_set(Package, Variant, Value),
    node(Package).

variant_not_default(Package, Variant, Value, 0)
 :- variant_value(Package, Variant, Value),
    variant_default_value(Package, Variant, Value),
    node(Package).

variant_not_default(Package, Variant, Value, 0)
 :- variant_value(Package, Variant, Value),
    variant_set(Package, Variant, Value),
    node(Package).


% The default value for a variant in a package is what is written
% in the package.py file, unless some preference is set in packages.yaml
variant_default_value(Package, Variant, Value)
 :- variant_default_value_from_package_py(Package, Variant, Value),
    not variant_default_value_from_packages_yaml(Package, Variant, _).

variant_default_value(Package, Variant, Value)
 :- variant_default_value_from_packages_yaml(Package, Variant, Value).

% Treat 'none' in a special way - it cannot be combined with other
% values even if the variant is multi-valued
:- 2 {variant_value(Package, Variant, Value): variant_possible_value(Package, Variant, Value)},
   variant_value(Package, Variant, "none").

% patches and dev_path are special variants -- they don't have to be
% declared in the package, so we just allow them to spring into existence
% when assigned a value.
auto_variant("dev_path").
auto_variant("patches").
variant(Package, "dev_path")
  :- variant_set(Package, Variant, _), auto_variant(Variant).
variant_single_value(Package, "dev_path")
  :- variant_set(Package, "dev_path", _).

% suppress warnings about this atom being unset.  It's only set if some
% spec or some package sets it, and without this, clingo will give
% warnings like 'info: atom does not occur in any rule head'.
#defined variant/2.
#defined variant_set/3.
#defined variant_single_value/2.
#defined variant_default_value/3.
#defined variant_possible_value/3.
#defined variant_default_value_from_packages_yaml/3.
#defined variant_default_value_from_package_py/3.

%-----------------------------------------------------------------------------
% Platform semantics
%-----------------------------------------------------------------------------
% one platform per node
1 { node_platform(Package, Platform) : node_platform(Packagee, Platform) } 1
  :- node(Package).

% if no platform is set, fall back to the default
node_platform(Package, Platform)
 :- node(Package),
    not node_platform_set(Package),
    node_platform_default(Platform).

% setting platform on a node is a hard constraint
node_platform(Package, Platform)
 :- node(Package), node_platform_set(Package, Platform).

% platform is set if set to anything
node_platform_set(Package) :- node_platform_set(Package, _).

#defined node_platform_set/2.  % avoid warnings

%-----------------------------------------------------------------------------
% OS semantics
%-----------------------------------------------------------------------------
% one os per node
1 { node_os(Package, OS) : os(OS) } 1 :- node(Package).

% node_os_set implies that the node must have that os
node_os(Package, OS) :- node(Package), node_os_set(Package, OS).
node_os_set(Package) :- node_os_set(Package, _).

% inherit OS along dependencies
node_os_inherit(Package, OS) :- node_os_set(Package, OS).
node_os_inherit(Dependency, OS)
  :- node_os_inherit(Package, OS), depends_on(Package, Dependency),
     not node_os_set(Dependency).
node_os_inherit(Package) :- node_os_inherit(Package, _).

% fall back to default if not set or inherited
node_os(Package, OS)
  :- node(Package),
     not node_os_set(Package), not node_os_inherit(Package),
     node_os_default(OS).

#defined node_os_set/2.

%-----------------------------------------------------------------------------
% Target semantics
%-----------------------------------------------------------------------------
% one target per node -- optimization will pick the "best" one
1 { node_target(Package, Target) : target(Target) } 1 :- node(Package).

% node_target_satisfies semantics
1 { node_target(Package, Target) : node_target_satisfies(Package, Constraint, Target) } 1
  :- node_target_satisfies(Package, Constraint).
node_target_satisfies(Package, Constraint)
  :- node_target(Package, Target), node_target_satisfies(Package, Constraint, Target).
#defined node_target_satisfies/3.

% The target weight is either the default target weight
% or a more specific per-package weight if set
target_weight(Target, Package, Weight)
  :- default_target_weight(Target, Weight),
     node(Package),
     not derive_target_from_parent(_, Package),
     not package_target_weight(Target, Package, _).

% TODO: Need to account for the case of more than one parent
% TODO: each of which sets different targets
target_weight(Target, Dependency, Weight)
  :- depends_on(Package, Dependency),
     derive_target_from_parent(Package, Dependency),
     target_weight(Target, Package, Weight).

target_weight(Target, Package, Weight)
  :- package_target_weight(Target, Package, Weight).

% can't use targets on node if the compiler for the node doesn't support them
:- node_target(Package, Target),
   not compiler_supports_target(Compiler, Version, Target),
   node_compiler(Package, Compiler),
   node_compiler_version(Package, Compiler, Version).

% if a target is set explicitly, respect it
node_target(Package, Target)
 :- node(Package), node_target_set(Package, Target).

% each node has the weight of its assigned target
node_target_weight(Package, Weight)
 :- node(Package),
    node_target(Package, Target),
    target_weight(Target, Package, Weight).

% compatibility rules for targets among nodes
node_target_match_pref(Dependency, Target)
  :- depends_on(Package, Dependency),
     node_target_match_pref(Package, Target),
     not node_target_set(Dependency, _).

node_target_match_pref(Dependency, Target)
  :- depends_on(Package, Dependency),
     node_target_set(Package, Target),
     not node_target_match_pref(Package, Target),
     not node_target_set(Dependency, _).

node_target_match_pref(Dependency, Target)
  :- depends_on(Package, Dependency),
     root(Package), node_target(Package, Target),
     not node_target_match_pref(Package, _).

node_target_match(Package, 1)
  :- node_target(Package, Target), node_target_match_pref(Package, Target).

derive_target_from_parent(Parent, Package)
  :- depends_on(Parent, Package), not package_target_weight(_, Package, _).


#defined node_target_set/2.
#defined package_target_weight/3.

%-----------------------------------------------------------------------------
% Compiler semantics
%-----------------------------------------------------------------------------

% one compiler per node
1 { node_compiler(Package, Compiler) : compiler(Compiler) } 1 :- node(Package).
1 { node_compiler_version(Package, Compiler, Version)
    : compiler_version(Compiler, Version) } 1 :- node(Package).
1 { compiler_weight(Package, Weight) : compiler_weight(Package, Weight) } 1
 :- node(Package).

% define node_compiler_version_satisfies/3 from node_compiler_version_satisfies/4
% version_satisfies implies that exactly one of the satisfying versions
% is the package's version, and vice versa.
1 { node_compiler_version(Package, Compiler, Version)
    : node_compiler_version_satisfies(Package, Compiler, Constraint, Version) } 1
  :- node_compiler_version_satisfies(Package, Compiler, Constraint).
node_compiler_version_satisfies(Package, Compiler, Constraint)
  :- node_compiler_version(Package, Compiler, Version),
     node_compiler_version_satisfies(Package, Compiler, Constraint, Version).
#defined node_compiler_version_satisfies/4.

% If the compiler version was set from the command line,
% respect it verbatim
node_compiler_version(Package, Compiler, Version) :- node_compiler_version_hard(Package, Compiler, Version).

% Cannot select a compiler if it is not supported on the OS
% Compilers that are explicitly marked as allowed
% are excluded from this check
:- node_compiler_version(Package, Compiler, Version), node_os(Package, OS),
   not compiler_supports_os(Compiler, Version, OS),
   not allow_compiler(Compiler, Version).

% If the compiler is what was prescribed from command line etc.
% or is the same as a root node, there is a version match

% Compiler prescribed in the root spec
node_compiler_version_match_pref(Package, Compiler, V)
 :- node_compiler_hard(Package, Compiler),
    node_compiler_version(Package, Compiler, V),
    not external(Package).

% Compiler inherited from a parent node
node_compiler_version_match_pref(Dependency, Compiler, V)
 :- depends_on(Package, Dependency),
    node_compiler_version_match_pref(Package, Compiler, V),
    node_compiler_version(Dependency, Compiler, V),
    not node_compiler_hard(Dependency, Compiler).

% Compiler inherited from the root package
node_compiler_version_match_pref(Dependency, Compiler, V)
 :- depends_on(Package, Dependency),
    node_compiler_version(Package, Compiler, V), root(Package),
    node_compiler_version(Dependency, Compiler, V),
    not node_compiler_hard(Dependency, Compiler).

compiler_version_match(Package, 1)
 :- node_compiler_version(Package, Compiler, V),
    node_compiler_version_match_pref(Package, Compiler, V).

#defined node_compiler_hard/2.
#defined node_compiler_version_hard/3.
#defined compiler_supports_os/3.
#defined allow_compiler/2.

% compilers weighted by preference according to packages.yaml
compiler_weight(Package, Weight)
 :- node_compiler(Package, Compiler),
    node_compiler_version(Package, Compiler, V),
    node_compiler_preference(Package, Compiler, V, Weight).
compiler_weight(Package, Weight)
 :- node_compiler(Package, Compiler),
    node_compiler_version(Package, Compiler, V),
    not node_compiler_preference(Package, Compiler, V, _),
    default_compiler_preference(Compiler, V, Weight).
compiler_weight(Package, 100)
 :- node_compiler(Package, Compiler),
    node_compiler_version(Package, Compiler, Version),
    not node_compiler_preference(Package, Compiler, Version, _),
    not default_compiler_preference(Compiler, Version, _).

#defined node_compiler_preference/4.
#defined default_compiler_preference/3.

%-----------------------------------------------------------------------------
% Compiler flags
%-----------------------------------------------------------------------------
% propagate flags when compilers match
inherit_flags(Package, Dependency)
 :- depends_on(Package, Dependency),
    node_compiler(Package, Compiler),
    node_compiler(Dependency, Compiler),
    compiler(Compiler), flag_type(FlagType).
node_flag_inherited(Dependency, FlagType, Flag)
 :- node_flag_set(Package, FlagType, Flag), inherit_flags(Package, Dependency).
node_flag_inherited(Dependency, FlagType, Flag)
 :- node_flag_inherited(Package, FlagType, Flag),
    inherit_flags(Package, Dependency).

% node with flags set to anythingg is "set"
node_flag_set(Package) :- node_flag_set(Package, _, _).

% remember where flags came from
node_flag_source(Package, Package) :- node_flag_set(Package).
node_flag_source(Dependency, Q)
 :- node_flag_source(Package, Q), inherit_flags(Package, Dependency).

% compiler flags from compilers.yaml are put on nodes if compiler matches
node_flag(Package, FlagType, Flag)
 :- not node_flag_set(Package),
    compiler_version_flag(Compiler, Version, FlagType, Flag),
    node_compiler(Package, Compiler),
    node_compiler_version(Package, Compiler, Version),
    flag_type(FlagType),
    compiler(Compiler),
    compiler_version(Compiler, Version).

node_flag_compiler_default(Package)
 :- not node_flag_set(Package),
    compiler_version_flag(Compiler, Version, FlagType, Flag),
    node_compiler(Package, Compiler),
    node_compiler_version(Package, Compiler, Version),
    flag_type(FlagType),
    compiler(Compiler),
    compiler_version(Compiler, Version).

% if a flag is set to something or inherited, it's included
node_flag(Package, FlagType, Flag) :- node_flag_set(Package, FlagType, Flag).
node_flag(Package, FlagType, Flag)
 :- node_flag_inherited(Package, FlagType, Flag).

% if no node flags are set for a type, there are no flags.
no_flags(Package, FlagType)
 :- not node_flag(Package, FlagType, _), node(Package), flag_type(FlagType).

#defined compiler_version_flag/4.
#defined node_flag/3.
#defined node_flag_set/3.

%-----------------------------------------------------------------------------
% How to optimize the spec (high to low priority)
%-----------------------------------------------------------------------------
% weight root preferences higher
%
% TODO: how best to deal with this issue?  It's not clear how best to
% weight all the constraints. Without this root preference, `spack solve
% hdf5` will pick mpich instead of openmpi, even if openmpi is the
% preferred provider, because openmpi has a version constraint on hwloc.
% It ends up choosing between settling for an old version of hwloc, or
% picking the second-best provider.  This workaround weights root
% preferences higher so that hdf5's prefs are more important, but it's
% not clear this is a general solution.  It would be nice to weight by
% distance to root, but that seems to slow down the solve a lot.
%
% One option is to make preferences hard constraints.  Or maybe we need
% to look more closely at where a constraint came from and factor that
% into our weights.  e.g., a non-default variant resulting from a version
% constraint counts like a version constraint.  Needs more thought later.
%

root(Package, 2) :- root(Package), node(Package).
root(Dependency, 1) :- not root(Dependency), node(Dependency).

% The highest priority is to minimize the:
% 1. Version weight
% 2. Number of variants with a non default value, if not set
% for the root(Package)
#minimize { Weight@15 : root(Package),version_weight(Package, Weight)}.
#minimize {
    Weight@14,Package,Variant,Value
    : variant_not_default(Package, Variant, Value, Weight), root(Package)
}.
% If the value is a multivalued variant there could be multiple
% values set as default. Since a default value has a weight of 0 we
% need to maximize their number below to ensure they're all set
#maximize {
    1@13,Package,Variant,Value
    : variant_not_default(Package, Variant, Value, Weight),
    not variant_single_value(Package, Variant),
    root(Package)
}.
#minimize{
    Weight@13,Provider
    : provider_weight(Provider, Weight), root(Provider)
}.

% Try to use default variants or variants that have been set
#minimize {
    Weight@11,Package,Variant,Value
    : variant_not_default(Package, Variant, Value, Weight), not root(Package)
}.
% Minimize the weights of the providers, i.e. use as much as
% possible the most preferred providers
#minimize{
    Weight@9,Provider
    : provider_weight(Provider, Weight), not root(Provider)
}.
% If the value is a multivalued variant there could be multiple
% values set as default. Since a default value has a weight of 0 we
% need to maximize their number below to ensure they're all set
#maximize {
    1@8,Package,Variant,Value
    : variant_not_default(Package, Variant, Value, Weight),
    not variant_single_value(Package, Variant),
    not root(Package)
}.

% Try to maximize the number of compiler matches in the DAG,
% while minimizing the number of nodes. This is done because
% a maximization on the number of matches for compilers is highly
% correlated to a preference to have as many nodes as possible
#minimize{ 1@7,Package : node(Package) }.
#maximize{ Weight@7,Package : compiler_version_match(Package, Weight) }.

% Choose more recent versions for nodes
#minimize{
    Weight@6,Package : version_weight(Package, Weight)
}.

% Try to use preferred compilers
#minimize{ Weight@5,Package : compiler_weight(Package, Weight) }.

% Maximize the number of matches for targets in the DAG, try
% to select the preferred target.
#maximize{ Weight@4,Package : node_target_match(Package, Weight) }.
#minimize{ Weight@3,Package : node_target_weight(Package, Weight) }.
