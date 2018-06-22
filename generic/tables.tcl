# This file contains the definition of tables that parameterize
#   the operation of nsbd.
# The variables in this file with the suffix "Keylist" are lists where 
#	every third item is the following:
#   1. A list of comment lines that apply to this keyword, suitable for
#	reading by a person editting a file that contains the keywords.
#   2. The keyword.
#   3. A number 1 if a list value is expected or 0 if a single item is expected
# The variables in this file with the suffix "Keytable" are tables
#   for use by nsbdParseContents to parse "nsbd" format files.
# The variables with the suffix "Keys" are lists of just keywords.
# Generation of man page source is also implemented in this source file.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 06 Nov 1996
#
# Copyright (C) 1996-2003 by Dave Dykstra and Lucent Technologies
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#  
# If those terms are not sufficient for you, contact the author to 
# discuss the possibility of an alternate license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

#
# empty procedure for auto loading this file
#
proc ensure-tables-loaded {} {
}

set fileTypes(nsbFile) nsb
set fileTypes(nsbPackageDescription) npd
set fileTypes(nsbRegistryDatabase) nrd
set fileTypes(nsbConfiguration) cfg
set fileTypes(nsbUpdate) nup
set fileKeywords(nsb) nsbFile
set fileKeywords(npd) nsbPackageDescription
set fileKeywords(nrd) nsbRegistryDatabase
set fileKeywords(cfg) nsbConfiguration
set fileKeywords(nup) nsbUpdate
set fileVersions(nsb) 1
set fileVersions(npd) 1
set fileVersions(nrd) 1
set fileVersions(cfg) 1
set fileVersions(nup) 1
set fileWarnUnknownKeys(nsb) 0
set fileWarnUnknownKeys(npd) 1
set fileWarnUnknownKeys(nrd) 1
set fileWarnUnknownKeys(cfg) 1
set fileWarnUnknownKeys(nup) 1
set fileTitles(nsb) "Not-So-Bad '.nsb'"
set fileTitles(npd) "Not-so-bad Package Description '.npd'"
set fileTitles(nrd) "Not-so-bad Registry Database '.nrd'"
set fileTitles(cfg) "Not-so-bad Configuration '.ncf'"
set fileTitles(nup) "Not-so-bad Update Description"
set filePurpose(nsb) \
  "describes the complete contents of a package"
set filePurpose(npd) \
  "contains a description of the source of a package for generating a '.nsb' file"
set filePurpose(nrd) \
  "contains the database of registered packages"
set filePurpose(cfg) \
  "contains configuration options for maintainers and users"
set filePurpose(nup) \
  "contains a description of an update"

#
# keylist and keytable for configuration
#
# this is split into two strings to avoid warnings from tcl2c
#
set cfgKeylist {
 {{Path to directory that NSBD uses for its support files (especially}
  {config.ncf and registry.nrd). Can also come from environment $NSBDPATH}
  {or $nsbdpath. Default is ~/.nsbd.  If overridden on the command line to}
  {be empty, NSBD does try to reference the files that are normally there.}}
nsbdpath 0

 {{Paths to configuration files.  If any of the paths are relative, they are}
  {relative to the "nsbdpath" keyword (normally ~/.nsbd).  Default is}
  {"config.ncf".  To override the default, this has to be used on the command}
  {line.  These are also processed inside each configuration file to include}
  {more nested configuration files.  However, later files have lower precedence}
  {than earlier files; any keyword (other than configFiles) which is set in}
  {in an earlier file is ignored in a later file.}}
configFiles 1

 {{Path to registry database files.  If any of the paths are relative, they}
  {are relative to the "nsbdpath" keyword (normally ~/.nsbd).  Default is}
  {"registry.nrd".  Later files have lower precedence than earlier files;}
  {any keyword (other than packages) which is set in in an earlier file is}
  {ignored in a later file; the packages list, however, is merged between all}
  {the files rather than ignored.  All automatically-generated updates are}
  {written to last file on the list; earlier registry files are read-only.}}
registryFiles 1

 {{Path to file in which to log messages.  If a relative path, it is relative}
  {to the "nsbdpath" keyword (normally ~/.nsbd).  Default is "updates.log".}}
logFile 0

 {{Number of days to accumulate log messages in the logFile before renaming}
  {it with an "old" prefix.  If set to 0, will grow without bounds and it}
  {will be the user's responsibility to truncate it.  Default 7.}}
logDays 0

 {{Level of messages to put into log file.  0: errors only; 1: also warnings;}
  {2: also maintainer notices; 3: also file changes; 4: also progress info;}
  {5: also per-file fetch messages for batched fetches; 6: reserved; 7: also}
  {debug messages.  Default 3.}}
logLevel 0

 {{Message level to display interactively.  0: errors only; 1: also warnings;}
  {2: also maintainer notices; 3: also file changes; 4: also progress info;}
  {5: also per-file fetch messages for batched fetches, and url fetch/post}
  {percent-done messages for those that take more than three seconds; 6: also}
  {percent-done messages for all url fetches/posts; 7: also debug messages.}
  {Default 4.}}
verbose 0

 {{Pathname for the PGP or compatible program, required if signatures are used.}
  {It is highly recommended to use a complete path to the program for security}
  {reasons.  If using PGP 5 or similar where the program is split into parts,}
  {specify the pgpv program; the corresponding pgpk and pgps programs must be}
  {in the same directory.  Command line options can also be included here; for}
  {example, NSBD assumes the language that PGP reports in is English, so if the}
  {default is set to another language you could add '+language=en' here.}}
pgp 0

 {{Variant of PGP that is referred to in the 'pgp' keyword.  Supported types}
  {are:}
  {  1. "pgp": works with at least pgp 2.6.2 and pgp 4.0.}
  {  2. "pgp5": works with at least pgp 5.0.}
  {  3. "gpg": works with gpg (the GNU Privacy Guard).}
  {Default is calculated from the 'pgp' keyword: if the first word of that}
  {keyword ends in "gpg" (where words are separated by whitespace), the variant}
  {is assumed to be "gpg"; if it ends in "pgpv", the variant is assumed to be}
  {"pgp5"; otherwise the variant is assumed to be "pgp".}}
pgpVariant 0

 {{Path to directory that PGP uses for its support files such as the public}
  {key ring and its configuration file.  Default is to let PGP figure it out.}
  {This keyword is available because the original PGP required this to be set}
  {in a $PGPPATH environment variable and couldn't be on the command line, so}
  {it couldn't be included in the 'pgp' keyword.}}
pgppath 0

 {{Pathname for the rsync program, used for retrieving rsync:// URLs.  Command}
  {line options can also be included here.  Default is 'rsync -z', but if you}
  {have rsync it is a good idea to set this keyword because if a package}
  {specifies both an rsync topUrl and a http multigetUrl, rsync will only be}
  {used if this keyword is explicitly set.}}
rsync 0

 {{Pathname for the breloc program, used for binary relocates by the "relocTop"}
  {keyword.  Default is 'breloc -r'.}}
breloc 0

 {{URL (of form "http://proxyhost[:portno][/]") of HTTP proxy server, if any.}
  {Default portno is 8080.  If not set here, default is from environment}
  {$HTTP_PROXY or $http_proxy.}}
http_proxy 0

 {{URL (of form "http://proxyhost[:portno][/]") of HTTP proxy server that can}
  {serve ftp URLs.  Ftp is only currently supported through the http server.}
  {Default portno is 8080.  If not set here, default is from environment}
  {$FTP_PROXY or $ftp_proxy.}}
ftp_proxy 0

 {{List of IP domains for which HTTP proxies should not be used.  If not set}
  {here, default is from environment $NO_PROXY or $no_proxy.}}
no_proxy 1

 {{Authorization to use for the http proxy in the form of username:password.}
  {Note that if this needs to be at all secure you should protect your}
  {configuration file from being read by other people.}}
proxyAuthorization 0

 {{User-Agent value to put in HTTP headers.}}
httpUserAgent 0
}
append cfgKeylist {
 {{Directory in which to put small scratch files, usually a RAM disk.}
  {If not set here, default is from environment $TMP or $tmp, or else /tmp.}}
tmp 0

 {{Directory in which to temporarily store files until all files in an update}
  {are successfully retrieved.  For best performance, should be in the same}
  {filesystem as all the packages are installed in.  If there is a failure}
  {during retrieval, the temporary files will remain there so they can be}
  {used on a subsequent attempt.  If a relative path, it is relative to the}
  {per-package installTop.  Default is ".nsbdtmp".}}
installTmp 0

 {{File creation mask to use on new files.  This is the Unix umask, in octal.}
  {Note that the permissions that are distributed with files in NSBD packages}
  {only indicate "rwx", that is, read, write and execute; those will apply to}
  {all protection levels (user, group, and other) unless masked by this key.}
  {Default is 022.}}
createMask 0

 {{List of paths and corresponding file permissions to use for those paths}
  {(after substitutions) in Unix-style octal.  This list is applied after any}
  {per-package pathPerms in the registry database.  Each list item is a Unix}
  {"glob" style expression ("*", "?", or "[]" wildcards) followed by whitespace}
  {followed by the file permissions to use when installing a file or directory}
  {whose path matches the expression.  The permissions are in Unix-style octal}
  {for user, group, and other, and may include setuid/setgid bits.  Also, if}
  {the permissions start with a plus sign ("+"), the permissions will be added}
  {to the default and if they start with a minus sign ("-"), the permissions}
  {will be subtracted from the default; if there is neither a plus or minus}
  {sign, the permissions will be overridden.  The default permissions for a}
  {file or directory are determined by the "createMask" configuration variable}
  {and the "mode" that is specified in the '.nsb' file (directories are assumed}
  {to be "rwx") which is repeated for user, group, and other.  The order of}
  {the expressions is significant: the first expression that matches a path,}
  {if any, is the one that will apply.  Paths that do not match any glob}
  {expression here will use the default permissions.}}
pathPerms 1

 {{Indentation length used for each level on generated files, range 1-8,}
  {default 4.  Each 8 spaces of ident is replaced by a tab.}}
generatedIndentLength 0

 {{Command that is able to execute commands in a window that prompt the user,}
  {for the rare cases when that is needed.  Must accept a "-T" option for the}
  {window title and a "-e" option for the command to execute.  Default is}
  {xterm.}}
termCommand 0

 {{Message digest (secure hashing) algorithm to use when generating '.nsb'}
  {files.  Supported types are "md5" and "sha1".  Default is sha1.  Sha1 is}
  {generally recognized as being more secure than md5, but it takes about}
  {twice the compute time to check.  Either algorithm will be accepted when}
  {reading '.nsb' files, regardless of the setting of this keyword.}}

mdType 0
 {{Default PGP identifiers of the maintainers of '.nsb' files that are}
  {created.  These should normally be the names and email addresses of the}
  {maintainers in the format "First Last (Comment) <email@domain>".  If}
  {a PGP variant is being used that reports the key ID on valid signatures,}
  {such as gpg or pgp 5.0, the identifier may instead be specified beginning}
  {with 0x followed by the hexadecimal key id (the letters A-F must be}
  {capitalized).}}
maintainers 1

	{{Default URL at which the PGP public key of the maintainer can be}
	 {found, if not already known by the user.  The ID for the key must}
	 {exactly match the given maintainer identifier.}}
{maintainers pgpKeyUrl} 0

 {{List of default supported executable types when installing files; that is}
  {names that describe a processor plus operating system that can execute}
  {files in the package.  This can be overridden on a per-package basis in}
  {the registration database.  It is suggested to use the value reported by}
  {GNU autoconf's "config.guess" script without any operating system version:}
  {a triple of processor type, vendor, and operating system name separated by}
  {dashes (for example, sparc-sun-solaris).  At a minimum, they need to be}
  {agreed upon between maintainers and users of packages if the users want to}
  {support multiple types.  If this is not set here or in the registration}
  {database, any executableType will be accepted.   Note: this default is not}
  {used for creating '.nsb' files although the subkeyword "extension" is used}
  {then.}}
executableTypes 1

	{{Alternate names accepted for this executable type.  May use "glob"}
	 {style wildcards ("*", "?", and "[]").  If you want to choose a short}
	 {local name for executableTypes you would list the short name as the}
	 {main type and the long name as an alias.  For example,}
	 {  executableTypes:}
	 {    solaris}
	 {      aliases: sparc-*-solaris}
	 {The registry database always has to have the executableType of the}
	 {original package, but a "%E" substitution in the "installTop" will}
	 {always use the executableType listed in the configuration file and}
	 {not an alias.}}
{executableTypes aliases} 0

	{{Value to use for %X substitutions with this executable type.  This is}
	 {intended for supplying a '.exe' extensions for types like cygwin that}
	 {need it.}}
{executableTypes extension} 0

	{{Newest supported operating system version for this executable}
	 {type, in the same format as the "version" keyword as described}
	 {in the Not-So-Bad Package Description files.  Larger numbers of}
	 {"minOSVersion" in installed packages will not be accepted because}
	 {they will not run.}}
{executableTypes maxOSVersion} 0

	{{Oldest supported operating system version for this executable type.}
	 {Smaller numbers of "maxOSVersion" in installed packages will not be}
	 {accepted because they will not run.  Note that this is rare, since}
	 {operating systems are usually upward compatible, (notable exception:}
	 {Unix System V Release 4.0).}}
{executableTypes minOSVersion} 0
}
append cfgKeylist {
 {{Default top level directory to install packages into.  If a relative path,}
  {it is relative to the directory from which NSBD is run.  May contain %P,}
  {%V, or %E which are replaced by the package name, the version number, or}
  {the executableType respectively.  The "installTop" directory must already}
  {exist; it will not be created.  Default is relocTop if set, otherwise}
  {~/nsbd. Note: this is not used when creating '.nsb' files.}}
installTop 0

 {{Default top level directory to relocate package files to: all occurrences}
  {of the string specified by "installTop" in the packages' '.nsb' files are}
  {replaced by this value, with differences in length padded by extra slashes.}
  {If a relative path, it is relative to the directory from which NSBD is run.}
  {May contain %P, %V, or %E which are replaced by the package name, the}
  {version number, or the executableType respectively.}}
relocTop 0

 {{Default path in which to store '.nsb' files when installing packages.}
  {If a relative path, it is relative to "installTop" (and may include}
  {".." components).  May contain %P, %V, or %E which are replaced by the}
  {package name, the version number, or the executableType respectively.}
  {If the nsbStorePath value is a directory, the default filename component}
  {is "%P.nsb".  Specifying the filename component as "%P%V.nsb" (or including}
  {%V in installTop and making nsbStorePath relative to installTop) is a good}
  {way to keep multiple versions of a package installed.  Default is the value}
  {of nsbdpath.}}
nsbStorePath 0

 {{List of additional substitutions to perform on "paths" when they are}
  {installed.  These are used when installing packages that were described in}
  {'.nsb' files, after the substitutions that were passed in the file and after}
  {any per-package substitutions.  Note: this value is not used when creating}
  {'.nsb' files.   See the description of this keyword in package description}
  {files for more details on the content.}}
pathSubs 1

 {{List of additional regular expression substitutions to perform on "paths"}
  {when they are installed, after applying "pathSubs".  Note: this value is}
  {not used when creating '.nsb' files.   See the description of this keyword}
  {in package description files for more details on the content.}}
regSubs 1

 {{List of additional backup substitutions to perform, after any per-package}
  {backupSubs.  These are applied after "pathSubs" and "regSubs".  The format}
  {is exactly the same as regSubs except that the only % substitution is %P,}
  {and the substitutions are for determining the path in which to save}
  {previously installed files when new versions are installed.  Any paths}
  {that match the regular expression in the first part will be backed up}
  {using the substitution in the second part.  The substituted path must}
  {be within the validPaths of the package.}}
backupSubs 1

 {{List of keywords that authorized maintainers of packages are allowed to}
  {remotely update in the package registry database via keywords in their}
  {'.nsb' files.  Note that some of these keys give a lot of power to the}
  {maintainers, but the values that you choose depend on how much you trust}
  {the maintainers.  Supported keys are these, with the associated conditions}
  {that must be true in order for the change to be allowed:}
  {  1. nsbUrl - '.nsb' file(s) at new nsbUrl must be identical to the}
  {      one that does the update.}
  {  2. maintainers (NOT IMPLEMENTED YET) - all PGP keys must either already}
  {      exist in the user's PGP public key ring or the keys at the pgpKeyUrl}
  {      must be sufficiently certified to satisfy PGP.}
  {  3. validPaths - all paths in the package must not conflict with any other}
  {      paths of previously installed packages under the same installTop.}
  {  4. preUpdateCommands - unconditional.}
  {  5. postUpdateCommands - unconditional.}
  {Unrecognized keywords are ignored.  Default is "nsbUrl".  Note that to}
  {disallow all keywords, you will need to put some unrecognized value here}
  {(such as "none") because empty lists are completely ignored.}}
maintainerUpdatableKeys 1

 {{Indicates the kinds of inter-package path conflict-checking to do.  Value}
  {should be one of}
  {  1. installs - make it an error to install paths that already exist in}
  {    another package.}
  {  2. deletes - do not delete paths that also exist in another package.}
  {  3. all - do both "installs" and "deletes".}
  {  4. none - do neither.}
  {Default is "all".}}
checkPathConflicts 0
}
append cfgKeylist {
 {{List of extra jobs for the -audit option.  By default -audit only identifies}
  {the files and directories that are listed in stored '.nsb' files (after}
  {applying substitutions) but do not exist or are not of the right length.}
  {The list can include any of the following:}
  {  1. checksig - check PGP signature on the stored '.nsb' files.}
  {  2. checksums - calculate the checksums for existing files and identify}
  {	those that do not match.}
  {  3. extra - identify files that are under directories in the registered}
  {	"validPaths" of selected packages but not referred to in any stored}
  {     '.nsb' file.  If the packages were selected by "all", identify all}
  {     extra files under the "installTop"(s) of the packages.  Paths that are}
  {     eliminated by pathSubs or regSubs in a config file or on the command}
  {     line are skipped.  If the packages were not selected by "all", any}
  {     registered and installed packages that have conflicting "validPaths"}
  {     with the selected packages must also be selected.}
  {  4. delete - delete identified extra files. Implies "extra".  May be}
  {	followed by a special construct of '%NN' where NN is a maximum percent}
  {     of total files to delete under each "installTop", in the range of 1}
  {     through 100.  Default 10.}
  {  5. repair - repair things that can be fixed locally: wrong permissions,}
  {	wrong hard links, or wrong symbolic links.}
  {  6. update - do -update on packages that have missing files or files that}
  {     have been identified to be incorrect, making sure those files get}
  {	reloaded.  If the package happens to have changed by the maintainer}
  {     since the last update, those changes will also be installed.  Implies}
  {     "repair".}
  {A maximum audit can be performed with "checksig,checksums,delete,update".}}
auditOptions 1

 {{Default minimum period to poll for changes to '.nsb' files.  Value is an}
  {integer followed by a letter (upper or lower case) 'm', 'h', 'd', or 'w'}
  {for minutes, hours, days, or weeks respectively.  If the integer is 0, no}
  {polling is done.  Default is 1d.  Note that this still requires that NSBD}
  {be invoked periodically with the '-poll' option, for example from cron.}
  {If it is invoked only once per day, for example, it won't make much sense}
  {to set values here of small numbers of minutes or hours.  To allow for}
  {slight differences in run time, 2 percent will be subtracted from the}
  {specified value.}}
minPollPeriod 0

 {{List of additional commands to run just before every package is about to be}
  {updated, after any per-package "preUpdateCommands".  The commands will be}
  {given a parameter that is the name of a file that will contain relevant}
  {information from the '.nsb' file, with a few differences; see the}
  {description of the same keyword in the '.nsb' file for details on the}
  {differences.  If any of the commands return a non-normal exit code, the}
  {update will be aborted.  If a command begins with the special character}
  {'@', its output will not be logged, otherwise output is logged at level 3.}
  {Note: this is not used when creating '.nsb' files.}}
preUpdateCommands 1

 {{List of additional commands to run just after every package has been}
  {updated, after any per-package "postUpdateCommands".  The commands will be}
  {passed all of the same information as the "preUpdateCommands" except for}
  {"temporaryTop".  If a command begins with the special character '@',}
  {its output will not be logged, otherwise output is logged at level 3.}
  {Note: this is not used when creating '.nsb' files.}}
postUpdateCommands 1

 {{Default list of paths on the maintainer side for which modification times}
  {can be preserved.  Each list item is a Unix "glob" style expression ("*",}
  {"?", or "[]" wildcards).  If this is not specified here or in the package}
  {'.npd' file (or on the command line), no modification times will be}
  {preserved.}}
pathPreserveMtimes 1

 {{List of optional file attributes to preserve on the user side, which is}
  {currently only this one attribute:}
  {  mtimes - preserve the modification times that were included by the}
  {    maintainer's "pathPreserveMtimes" keyword.}
  {Default is "mtimes"; to not preserve, set this to "none".}}
preserves 1
}
set cfgKeys ""
catch {unset cfgKeytable}
foreach {c k v} $cfgKeylist {
    lappend cfgKeys $k
    set cfgKeytable($k) $v
}

set cfgnpdKeys {maintainers {maintainers pgpKeyUrl} pathPreserveMtimes}
set envCfgKeys {nsbdpath ftp_proxy http_proxy no_proxy tmp}

set undocumentedCfgKeys "postLength 0"
foreach {k v} $undocumentedCfgKeys {
    lappend cfgKeys $k
    lappend cfgKeytable($k) $v
}

# don't set the config executableTypes in the config contents, so those
#   can be used for for eliminating unwanted %E files in a package
# the command-line setting will be retrieved later when needed
# don't override pathSubs and regSubs because they will be applied to
#   the '.nsb' file contents
set cfgCmdExceptions "executableTypes pathSubs regSubs"

# the first one here is the default when generating
set knownMdTypes {sha1 md5}

#
# keylist for keys that are common to npd, nsb, and nup
# The 'package' key is not here because the comment is different
#
set npdNsbNupKeylist {
 {{Version number of the package.  The number is a series of integers}
  {separated by non-integers.  The suffixes 'a' and 'b' on an integer (upper}
  {or lower case) indicate 'alpha' and 'beta' and are considered to be older}
  {than the same integer without 'a' or 'b'.  Whenever a %V path substitution}
  {is encountered, spaces and slashes in a version will be replaced by dashes.}
  {If there is no version specified, the "generatedAt" field will be used}
  {as a version for many purposes.}}
version 0

 {{One-line description of the package.}}
summary 0

 {{Multi-line description of the package.}}
description 1

 {{Multi-line release note, displayed as an informational message when}
  {package is installed.}}
releaseNote 1

 {{PGP user identifiers of the maintainers of the package.  These should}
  {also be the names and email addresses of the maintainers in the format}
  {"First Last (Comment) <email@domain>".}}
maintainers 1

	{{URL at which the PGP public key of the maintainer can be found, if}
	 {not already known by the user.  The primary user ID for the key}
	 {must exactly match the given maintainer identifier.}}
{maintainers pgpKeyUrl} 0

 {{Parameters that are defined by preUpdateCommands or postUpdateCommands.}
  {These are simply passed through to the file that those commands see.}}
updateParameters 1

 {{Executable types supported in this package if it contains executables;}
  {that is, names that describe a processor plus operating system that can}
  {execute programs in the package.  It is suggested to use the value reported}
  {by GNU autoconf's "config.guess" script without any operating system}
  {version: a triple of processor type, vendor, and operating system name}
  {separated by dashes (e.g. sparc-sun-solaris).  At a minimum, they need to}
  {be agreed upon between maintainers and users of packages if the users want}
  {to support multiple types.}}
executableTypes 1
}
set npdNsbNupKeys "package"
foreach {c k v} $npdNsbNupKeylist {
    lappend npdNsbNupKeys $k
}

#
# keylist for keys that are copied from npd to nsb
# The 'package' key is not here because the comment 
#   is different in npd and nsb
#
# this is split into two strings to avoid errors after tcl2c
#
set npdNsbKeylist [concat $npdNsbNupKeylist {
	{{Minimum version number of the operating system that the package}
	 {works on for this executableType, in the same number format as}
	 {the "version" keyword.}}
{executableTypes minOSVersion} 0

	{{Maximum version number of the operating sytem that the package works}
	 {on for this executableType.  Note that this is rare, since operating}
	 {systems are usually upward compatible (notable exception: Unix}
	 {System V Release 4.0).}}
{executableTypes maxOSVersion} 0

 {{List of other NSBD-compliant package names that are required by this}
  {package.}}
requiredPackages 1

	{{Minimum version level for required package, if any.}}
{requiredPackages minVersion} 0

	{{Minimum date/time at which the '.nsb' file of the required package}
	 {was generated, in the same format as the "generatedAt" field.  The}
	 {time, day of week, and/or timezone may be ommitted leaving just a}
	 {date.}}
{requiredPackages minGeneratedAt} 0

	{{Maximum version level for required package, if any.}}
{requiredPackages maxVersion} 0

	{{Maximum date/time at which the '.nsb' file of the required package}
	 {was generated, in the same format as the "generatedAt" field.  The}
	 {time, day of week, and/or timezone may be ommitted leaving just a}
	 {date.}}
{requiredPackages maxGeneratedAt} 0

	{{URL of a '.nsb' file for required package.  If omitted and the user}
	 {does not already have the required package, the user will only see}
	 {a warning but then installation will proceed.  May contain %P, %V,}
	 {or %E which will be replaced by the required package name, the}
	 {required package minVersion, or the executableType respectively.}}
{requiredPackages nsbUrl} 0
}]
append npdNsbKeylist {
 {{Minimum poll period to suggest to the user.  Value is an integer followed}
  {by a letter (upper or lower case) 'm', 'h', 'd', or 'w' for minutes, hours,}
  {days, or weeks respectively.  If the integer is 0, no polling is done.}
  {Default is to use user's default.}}
minPollPeriod 0

 {{Top level install directory to suggest to the user.  If a relative path,}
  {relative to the user's default installTop.  May begin with a tilde (~)}
  {indicating the user's home directory.  May contain %P, %V, or %E which are}
  {replaced by the package name, the version number, or the executableType}
  {respectively.  Also used to determine which path to relocate when the user}
  {sets "relocTop": if the package has compiled-in paths, it is a good idea}
  {to set the "prefix" to have a large number of extra trailing slashes (I}
  {suggest a total of 64 bytes) to allow the user flexibility in choosing a}
  {path to relocate to; the extra slashes do not need to be specified here,}
  {however.}}
installTop 0
 
 {{Command list to suggest to the user to run just before this package is about}
  {to be updated.  The commands will be given a parameter that is the name of a}
  {file that will contain relevant information from the '.nsb' file, with these}
  {differences:}
  {  1. The beginning keyword will be "nsbUpdate" instead of "nsbFile".}
  {  2. There will be an extra keyword "temporaryTop" that is the name of}
  {     the directory that contains the new versions of changing files.}
  {  3. The "installTop" keyword will be there after substitutions.}
  {  4. "maintainers" will contain the PGP user id of the package signer.}
  {  5. "paths" will contain only those files that are changing, after}
  {     substitutions have been applied and without subkeywords.}
  {  6. An extra keyword "removePaths" will list files to be removed.}
  {If any of the commands return a non-normal exit code, the update will be}
  {aborted.}}
preUpdateCommands 1

 {{Command list to suggest to the user to run just after this package has been}
  {updated.  The commands will be passed all of the same information as the}
  {"preUpdateCommands" except for "temporaryTop".}}
postUpdateCommands 1

 {{Uniform Resource Locator (URL) at which the '.nsb' file(s) for this}
  {package can be found.  The protocols http:, ftp:, and rsync: are supported.}
  {May contain %P, %V, or %E which are replaced by the package name, all}
  {supported version numbers, or all supported executableTypes respectively.}
  {If a %V is used, will also look at the name with a missing (empty) version}
  {number to discover new available versions.  If there are multiple '.nsb'}
  {files for this package, they should all contain the same value for this}
  {keyword.  If the value here is different from what the user has registered,}
  {the user's registered value will probably change immediately upon}
  {installation of the '.nsb' file (unless the user has set up manual}
  {intervention).}}
nsbUrl 0

 {{Uniform Resource Locator (URL) for the base of all files listed under the}
  {"paths" keyword.  The protocols http:, ftp:, and rsync: are supported.  May}
  {contain %P, %V, or %E which are replaced by the package name, the version,}
  {or the first executable type listed in executableTypes respectively.  May}
  {instead (or in addition) have a "multigetUrl" keyword.}}
topUrl 0

 {{Uniform Resource Locator (URL) for a program, such as a CGI script that}
  {uses nsbd -multigetFiles or -multigetPackage, that is able to retrieve}
  {multiple files on a single http connection using the "NSBD multiget}
  {protocol" for improved performance over having a separate http connection}
  {per file.  May contain %P, %V, or %E which are replaced by the package}
  {name, the version, or the first executable type listed in executableTypes}
  {respectively.}}
multigetUrl 0

 {{List of substitutions to perform on "paths" when they are installed.  Each}
  {list item has two parts separated by whitespace: the first part is the part}
  {to match and the second part is the part to substitute.  The second part}
  {can be missing if the match part is to be deleted (and if the match part}
  {matched the whole path the file will not be installed at all).  The match}
  {part may contain "glob" style wildcards ("*", "?", and "[]").  The match is}
  {made from the beginning of the path to the end of directories; for example,}
  {lib/tcl will not match lib/tcl7.5 but will match the first two components}
  {of lib/tcl/libtcl.a.  The match part may contain %E to match any of the}
  {"executableTypes", %V to match the "version", or %P to match the package}
  {name.  If the match part contains %E, paths that match non-applicable}
  {executableTypes will not installed.  For example, a path of "bin/prog.%E"}
  {and a pathSub of "bin/prog.%E bin/prog" is a good way to include multiple}
  {executable types in the same package but only install one.}}
pathSubs 1

 {{List of regular expression substitutions to be performed on "paths" when}
  {they are installed after applying "pathSubs".  Each list item has two}
  {parts separated by whitespace: the first part is a regular expression like}
  {that of the Unix "egrep" program and the second part is the substitution.}
  {The substitution can contain & to include the pattern matched or \n, where}
  {n is a decimal number, to include the n'th parenthesized subexpression.}
  {The substitution can be empty if the matched expression is to be deleted}
  {(and if the match part matched the whole path the file will not be}
  {installed at all).  The results of the substitution must be strictly below}
  {the top directory.  The match part may contain %E to match any of the}
  {"executableTypes", %V to match the "version", or %P to match the package}
  {name.  If the match part contains %E, paths that match non-applicable}
  {executableTypes will not be installed.  For example, having paths ending}
  {in ".%E" and having a regSub of "\.%E$" is a good way to include multiple}
  {executable types in the same package but only install one.}}
regSubs 1

 {{Indicates that the paths under "topUrl" or "multigetUrl" have already been}
  {pre-substituted (that is, pre-installed).  This is useful for redistribution}
  {of packages.  When set to "nsbFile" it indicates that the "pathSubs" and}
  {"regSubs" from the '.nsb' file have been applied, and when set to "all" it}
  {indicates that the substitutions from config and registry files have also}
  {been applied.  The latter is only useful when the config and registry files}
  {are shared between maintainer and user, so it makes most sense that "all" be}
  {reserved for the user to specify on the command line and for the maintainer}
  {to only set this to "nsbFile" (or don't set it at all).}}
urlPresubstitutions 0

 {{Suggested list of valid paths, if the default calculated from "paths" is}
  {not sufficient.  Valid paths are relative to the top level directory, after}
  {substitutions.  Unix-style file wildcards ("glob" style "*", "?", or "[]")}
  {may be included.  If a path ends in "/" here, all paths below that directory}
  {are valid.  To reserve all paths under the top level directory, use "*".}}
validPaths 1
}
set npdNsbKeys "package"
foreach {c k v} $npdNsbKeylist {
    lappend npdNsbKeys $k
}

#
# keylist and keytable for npd
#
set npdKeylist [concat {
 {{Name for the package.  The package name will be used for the filename of}
  {the '.nsb' file, so it must be short and made up of only alphanumeric}
  {characters or the characters '!', '_', '.', '+', or '-'.   Default is the}
  {base part of the '.npd' filename.}}
package 0
} $npdNsbKeylist {

 {{Path of the local base directory of the "paths" keyword to use when creating}
  {'.nsb' files.  This is relative to the directory that NSBD is run from, or}
  {a complete pathname.  Defaults to ".".}}
localTop 0

 {{List of pathnames relative to "localTop" to include in the package, unless}
  {excluded by the "excludePaths" keyword.  No pathname may include ".."}
  {components or start with "/" or "~" (that is, they must be strictly under}
  {the top level).  If the pathname refers to a directory, all files below}
  {that directory will be included recursively.  May use Unix "glob" style file}
  {wildcards ("*", "?", or "[]").  A %E will match all "executableTypes", and a}
  {%V will match the "version".  If a %E is present, a %X may also be present}
  {to substitute the value defined by "executableTypes extension".  If a file}
  {is a relative symbolic link to a file that is under the top level of the}
  {package, the pathname will be included in the package as a link rather than}
  {as the file it refers to.  IMPORTANT NOTE: the paths that are found by the}
  {list here are also used as the basis (after substitutions) of the default}
  {suggested "validPaths" when someone registers for your package, unless you}
  {explicitly include the validPaths keyword.  Most significantly, if you want}
  {to reserve an entire directory for future additions to your package, you}
  {should include the entire directory here or manually set "validPaths."}}
paths 1

 {{List of paths to exclude from the "paths" list.  May contain Unix "glob"}
  {style wildcards ("*", "?", or "[]").}}
excludePaths 1

 {{List of paths (before substitutions) and corresponding file permission}
  {modes.  Each list item is a Unix "glob" style expression ("*", "?", or "[]"}
  {wildcards) followed by whitespace followed by the file permission mode to}
  {use when installing the file.  The expression may contain %E which will}
  {match all "executableTypes" or %V which will match the "version".  The mode}
  {may contain any of "r", "w", or "x" in any order for readable, writable,}
  {and executable.  The order of the expressions is significant: the first}
  {expression that matches a path, if any, is the one that will apply.  For}
  {example, if the first list item is "*bin/* rwx" and the second item is}
  {"* rw", then any file in a bin directory will get a mode of "rwx" and}
  {every other file will get a mode of "rw".  Paths that do not match any}
  {glob expression here will use the mode of the original file.}}
pathModes 1

 {{List of paths for which modification times can be preserved.  Each list item}
  {is a Unix "glob" style expression ("*", "?", or "[]" wildcards).  If this is}
  {not specified here or in the configuration file (or on the command line), no}
  {modification times will be preserved.}}
pathPreserveMtimes 1
}]
set npdKeys ""
catch {unset npdKeytable}
foreach {c k v} $npdKeylist {
    lappend npdKeys $k
    set npdKeytable($k) $v
}

#
# keylist and keytable for nsb
# Note: the comments don't matter here at run time, because nsb files are
#  not generated with the intention of being editted by people, but the
#  comments are used in generating the documentation.
#
set nsbKeylist [concat {
 {{Free-format description of the program that created this file.}}
generatedBy 0

 {{Time at which this file was created in the preferred HTTP/1.0 format;}
  {for example, "Sun, 06 Nov 1994 08:49:37 GMT".}}
generatedAt 0

 {{Name for the package.  The package name will be used for the filename of}
  {the '.nsb' file, so it must be short and made up of only alphanumeric}
  {characters or the characters '!', '_', '.', '+', or '-'.}}
package 0
} $npdNsbKeylist {

 {{List of relative pathnames in the package.  No pathname may include ".."}
  {components or start with a "/" or "~".  Components of pathnames are}
  {separated by "/" even on PCs.  Pathnames ending in "/" indicate a directory.}}
paths 1

	 {{Pathname relative to top (below it) that the path is symbolically}
	  {linked to.}}
{paths linkTo} 0

	 {{Pathname relative to top (below it) that the path is hard-linked to.}}
{paths hardLinkTo} 0

 	{{Length of file at the path in bytes, maximum 2^31-1.  Not present}
	 {for directories or links.}}
{paths length} 0

 	{{32-byte hexadecimal (ASCII characters 0-9 and a-f) md5 message}
	 {digest (checksum) of the file at path.  Not present for directories}
	 {or links.}}
{paths md5} 0

 	{{40-byte hexadecimal (ASCII characters 0-9 and a-f) sha1 message}
	 {digest (secure hash, checksum) of the file at path.  Not present}
	 {for directories or links.}}
{paths sha1} 0

 	{{Permission modes of the file.  May contain any of "r", "w", or "x" in}
	 {any order for readable, writable, and executable.  Default is "rw".}
	 {Not present for directories or links.}}
{paths mode} 0

 	{{Modification time of the file, in seconds since January 1, 1970 GMT.}
	 {Only present for files that match a "pathPreserveMtimes" pattern.}
	 {Not present for directories or links.}}
{paths mtime} 0
}]
set nsbKeys ""
catch {unset nsbKeytable}
foreach {c k v} $nsbKeylist {
    lappend nsbKeys $k
    set nsbKeytable($k) $v
}

#
# keylist and keytable for nup
set nupKeylist [concat {
 {{Free-format description of the program that created the '.nsb' file.}}
generatedBy 0

 {{Time at which this file was created in the preferred HTTP/1.0 format;}
  {for example, "Sun, 06 Nov 1994 08:49:37 GMT".}}
generatedAt 0

 {{Name for the package.}}
package 0
} $npdNsbNupKeylist {

 {{Directory that files that are being updated are temporarily installed in.}}
temporaryTop 0

 {{Directory that files that are being updated are permanently installed in.}}
installTop 0

 {{List of pathnames relative to the top that are being updated, after}
  {substitutions.  Components of pathnames are separated by "/" even on PCs.}
  {Pathnames ending in "/" indicate a directory.}}
paths 1

 {{List of pathnames that are being removed from the package.  Pathnames ending}
  {in "/" indicate a directory.  NOTE: a directory removed from a package does}
  {not necessarily mean that the directory itself is to be removed if there are}
  {other files still in the directory.}}
removePaths 1
}]
set nupKeys ""
catch {unset nupKeytable}
foreach {c k v} $nupKeylist {
    lappend nupKeys $k
    set nupKeytable($k) $v
}
# keys that are copied from nsb to nup
set nsbNupKeys [concat [list generatedBy generatedAt] $npdNsbNupKeys]
# keys that are copied from nsb to nup for only internal use (not written out)
lappend nsbNupKeys topUrl multigetUrl urlPresubstitutions validPaths

#
# keylist and keytable for registry database
#
# this is split into two strings to avoid errors after tcl2c
#
set nrdKeylist {
 {{Set this to anything non-empty to regenerate the keyword comment template}
  {in the registry database file whenever the file is updated.  This file is}
  {recreated whenever there is an update so there is a little extra overhead.}}
regenerateComments 0

 {{List of registered package names.}}
packages 1

	{{The name of the package as distributed by the maintainer.  This}
	 {allows the user to register the package under a different name.}
	 {Defaults to the name the package is registered under.}}
{packages distributedPackageName} 0

	{{List of identifiers for the PGP public keys that are authorized to}
	 {update the package.  These must be the complete, primary PGP user}
	 {IDs listed in public keys in the PGP public key ring.  If missing,}
	 {will require -ignoreSecurity command line flag to install.}}
{packages maintainers} 1

	{{List of executable types accepted for this package; that is, names}
	 {that describe a processor plus operating system that can execute the}
	 {package.  Should match names used in "executableTypes" configuration}
	 {keyword, if there, or one of the executableTypes "aliases" listed in}
	 {the configuration file.  If this keyword is missing here any type in}
	 {the "executableTypes" configuration keyword will be accepted.  If the}
	 {"nsbUrl" contains a %E, this value will be used in place of the %E}
	 {(unless overridden on the command line) so it may not be missing in}
	 {that case.}}
{packages executableTypes} 1

	{{Automatically generated list of versions that are installed for}
	 {this package.  Unlike "executableTypes", this is not a filter of}
	 {acceptable versions; any version is always accepted.  Note that if}
	 {the '.nsb' files for different versions are stored in different}
	 {places because of a %V in "nsbStorePath" (or "installTop" if}
	 {"nsbStorePath" is relative to that), then old versions will need to}
	 {be manually removed by the user (or if a maintainer re-releases an}
	 {old version with an empty list of paths it will also be removed).}}
{packages versions} 1

	{{Top level directory to install package into.  If a relative path, it}
	 {is relative to "installTop" in the configuration file.  May contain}
	 {%P, %V, or %E which are replaced by the package name, the version}
	 {number, or the executableType respectively.  The installTop directory}
	 {must already exist before it is used; it will not be created.}
	 {Defaults to "relocTop" if set, otherwise defaults to the value of}
	 {"installTop" in the configuration file.}}
{packages installTop} 0

	{{Top level directory to relocate package files to: all occurrences}
	 {of the string specified by "installTop" in the packages' '.nsb' files}
	 {are replaced by this value, with differences in length padded by}
	 {extra slashes.  If a relative path, it is relative to "relocTop" in}
	 {the configuration file.  May contain %P, %V, or %E which are replaced}
	 {by the package name, the version number, or the executableType}
	 {respectively.  Defaults to "relocTop" in the configuration file.}}
{packages relocTop} 0

	{{Path in which to store '.nsb' file when installing package.  May}
	 {contain %P, %V, or %E which are replaced by the package name, the}
	 {version number, or the executableType respectively.  Defaults to}
	 {value in configuration file; see description of keyword there for}
	 {more details of the content.}}
{packages nsbStorePath} 0
}
append nrdKeylist {
        {{List of additional substitutions to perform on "paths" when they}
         {are installed.  These are used when installing packages that were}
	 {described in '.nsb' files, after the substitutions that were passed}
	 {in the file.  See the description of this keyword in Not-So-Bad}
	 {Package Description files for more details on the content.}}
{packages pathSubs} 1

        {{List of additional regular expression substitutions to perform on}
	 {"paths" when they are installed, after applying "pathSubs".  See the}
	 {description of this keyword in package description files for more}
	 {details on the content.}}
{packages regSubs} 1

       	{{List of backup substitutions to perform.  These are applied after}
	 {"pathSubs" and "regSubs".  The format is exactly the same as regSubs}
	 {except that the only % substitution is %P, and the substitutions are}
	 {for determining the paths in which to save previously installed files}
	 {when new versions are installed.  Any paths that match the regular}
	 {expression in the first part will be backed up using the substitution}
	 {in the second part.  The substituted path must be within the}
	 {validPaths of the package.  Default for a package called "nsbd"}
	 {is "bin/nsbd$ lib/nsbd/oldnsbd".}}
{packages backupSubs} 1

	{{List of valid paths relative to the top level directory, after}
	 {substitutions.  Unix-style file wildcards ("*", "?", or "[]") may be}
	 {included, and a %X may be used for the "executableTypes extension".}
	 {If a path ends in "/", all paths below that directory are allowed.}
	 {The default is no paths are valid; to allow all paths, use "*".  Note}
	 {that this may not necessarily improve overall security if executables}
	 {are distributed and then executed; those executables will then have}
	 {complete access that the user who runs them has.  However, these can}
	 {help security if, for example, distribution is done with a user id}
	 {that is more trusted than the one used for execution.  They also}
	 {prevent accidental overwrites and assist audits.}}
{packages validPaths} 1

	{{List of paths and corresponding file permissions to use for those}
	 {paths (after substitutions) in Unix-style octal.  Additional items}
	 {can be added in the same keyword in the configuration file; see the}
	 {description there for more details on the content.}}
{packages pathPerms} 1

	{{List of paths and corresponding groups to use for those paths (after}
	 {substitutions).  Each list item is a Unix "glob" style expression}
	 {("*", "?", or "[]" wildcards) followed by whitespace followed by the}
	 {group to use when installing a file or directory whose path matches}
	 {the expression.  The user id that NSBD is running under must have the}
	 {permission to change files to that group, which usually means the}
	 {user id must be a member of that group.}}
{packages pathGroups} 1

	{{URL of original '.nsb' file.  Required if updates are desired.}
	 {May contain %P, %V, or %E which are replaced by the registered}
	 {package name, version numbers, or executableTypes respectively.}
	 {If a %V is used, will also look at the name with a missing (empty)}
	 {version number to discover new available versions.  If a %E is}
	 {included, only the executableTypes that are explicitly registered}
	 {for this package will be looked at; will not default to the value}
	 {in the configuration file (to avoid timeouts looking for '.nsb'}
	 {files that may not exist for a given package).}}
{packages nsbUrl} 0

	{{Minimum period to poll for changes to '.nsb' files.  Value is}
	 {an integer followed by a letter (upper or lower case) 'm', 'h',}
	 {'d', or 'w' for minutes, hours, days, or weeks respectively.  If}
	 {the integer is 0, no polling is done.  Defaults to value in}
	 {configuration file or 1d.  Note that this still requires that NSBD}
	 {be invoked periodically with the '-poll' option, for example from}
	 {cron.  If it is invoked only once per day, for example, it won't}
	 {make much sense to set values here of small numbers of minutes or}
	 {hours.  To allow for slight differences in run time, 2 percent will}
	 {be subtracted from the specified value.}}
{packages minPollPeriod} 0

	{{Automatically generated time of when the package was last polled}
	 {successfully (with no errors), in the preferred HTTP/1.0 format.}}
{packages lastTimePolled} 0

	{{Automatically generated server time of when the package was last}
	 {polled successfully, in the preferred HTTP/1.0 format.  This is}
	 {saved separately from lastTimePolled because time on the server}
	 {may differ from time on the client.}}
{packages lastServerPollTime} 0

	{{List of commands to run just before a package is about to be}
	 {updated.  Additional commands may be specified in configuration}
	 {file.  The commands will be given a parameter that is the name of}
	 {a file that will contain all relevant information from the '.nsb'}
	 {file, with a few differences; see the description of the same}
	 {keyword in the '.nsb' file for details on the differences.  If any}
	 {of the commands return a non-normal exit code, the update will be}
	 {aborted.  If a command begins with the special character '@', its}
         {output will not be logged, otherwise output is logged at level 3.}}
{packages preUpdateCommands} 1

	{{List of commands to run just after a package has been updated.}
	 {The commands will be passed all the same information as the}
	 {"preUpdateCommands" except for the "temporaryTop" field.}
	 {Additional commands may be specified in configuration file.}
	 {If a command begins with the special character '@', its output}
	 {will not be logged, otherwise output is logged at level 3.}}
{packages postUpdateCommands} 1
}
catch {unset nrdKeytable}
set nrdKeys ""
foreach {c k v} $nrdKeylist {
    lappend nrdKeys $k
    set nrdKeytable($k) $v
    set kc [lrange $k 1 end]
}

#
# Generate the man page
#
proc makeNsbdMan {{filename "nsbd.1"}} {
    withOpen fd $filename "w" {
	puts $fd {.TH NSBD 1 ""}
	puts $fd ".SH NAME"
	puts $fd "nsbd - Not-So-Bad Distribution"
	puts $fd ".SH SYNOPSIS"
	puts $fd [join [manSub [split [nsbdSynopsis] "\n"]] "\n.br\n"]
	puts $fd ".SH DESCRIPTION"
	puts $fd [join [manSub [split [nsbdOperation] "\n"]] "\n"]
	puts $fd ".SH GETTING STARTED"
	puts $fd [join [manSub [split [nsbdGettingStarted] "\n"]] "\n"]
	puts $fd ".SH SECURITY MODEL"
	puts $fd [join [manSub [split [nsbdSecurityModel] "\n"]] "\n"]
	puts $fd ".SH OPTIONS"
	puts $fd "These are the command-line options that NSBD supports:"
	ensure-options-loaded
	global optionList
	foreach {c s v} $optionList {
	    if {$c != ""} {
		puts $fd ".IP \"[join $s { or }]\" 4"
		puts $fd [join [manSub $c] "\n"]
	    }
	}
	puts $fd ".SH FILE FORMAT"
	ensure-nsbdformat-loaded
	global nsbdFormatSummary
	puts $fd "All NSBD files have the same basic format."
	puts $fd [join [manSub $nsbdFormatSummary] "\n"]
	puts $fd {For a more detailed description see "nsbd -help fileformat".}
	makeNsbdFileMan $fd cfg
	makeNsbdFileMan $fd nrd
	makeNsbdFileMan $fd npd
	makeNsbdFileMan $fd nsb npd
	puts $fd ".SH EXAMPLES"
	puts $fd [join [manSub [split [nsbdExamples] "\n"]] "\n"]
	puts $fd ".SH VERSION"
	puts $fd "This man page was generated [currentTime] by [nsbdVersion]."
	puts $fd ".PP"
	puts $fd "NSBD was written by Dave Dykstra <dwd@bell-labs.com>."
	puts $fd ".br"
	puts $fd "Bell Labs, Innovations for Lucent Technologies."
	return $filename
    }
}

proc makeNsbdFileMan {fd fileType {otherFileType ""}} {
    upvar #0 ${fileType}Keylist keylist
    global fileTitles fileKeywords fileVersions filePurpose
    puts $fd ".SH \"Keywords in $fileTitles($fileType) file\""
    puts $fd ".PP"
    puts $fd "This file $filePurpose($fileType)."
    puts $fd ".PP"
    puts $fd ".IP $fileKeywords($fileType): 4"
    puts $fd "Identifies file type and version.  Current version is $fileVersions($fileType)."
    set nestlevel 1
    foreach {c k v} $keylist {
	set newlevel [llength $k]
	if {$newlevel > $nestlevel} {
	    puts $fd ".RS [expr {4 * ($newlevel - $nestlevel)}]"
	} elseif {$newlevel < $nestlevel} {
	    puts $fd ".RE [expr {4 * ($nestlevel - $newlevel)}]"
	}
	set nestlevel $newlevel
	puts $fd ".IP [lindex $k [expr {$newlevel - 1}]]: 4"
	if {$otherFileType != ""} {
	    upvar #0 ${otherFileType}Keylist otherKeylist
	    foreach {c2 k2 v2} $otherKeylist {
		if {($k == $k2) && ($c == $c2)} {
		    set c [list "Same as in $fileTitles($otherFileType) file."]
		    break
		}
	    }
	}
	puts $fd [join [manSub $c 4] "\n"]
    }
    if {$nestlevel > 1} {
	puts $fd ".RE [expr {4 * $nestlevel - 1}]"
    }
    puts $fd ".PP"
}

#
# Substitute a text message (a list of text lines actually) for use in
#  an nroff -man page.  Numbered lists are expected to have been represented
#  indented with digits followed by a period.  Nested numbered lists are not
#  supported.  Non-numbered indented lines are put in no-fill regions.
#
proc manSub {msg {indentlevel 0}} {
    set newmsg ""
    set inlist 0
    set indented 0
    set nofill 0
    foreach line $msg {
	incr nofill -1
	if {($nofill <= 0) &&
		[regexp {^[ 	]+([0-9]+\.)[ 	]*(.*)} $line x n rest]} {
	    # whitespace followed by numbers
	    if {!$inlist} {
		set inlist 1
		if {!$indented && ($indentlevel > 0)} {
		    # before this point, the text was already indented
		    #  $indentlevel spaces, but breaking here into a new
		    #  paragraph would lose that indent, so add to the
		    #  indent here and then subtract it at the end
		    set indented 1
		    lappend newmsg ".RS $indentlevel"
		}
	    }
	    lappend newmsg ".IP $n 4"
	    set line $rest
	} elseif {[regexp {^[ 	]+(.*)} $line x rest]} {
	    # white space not followed by numbers
	    if {$inlist} {
		set line $rest
	    } elseif {$nofill <= 0} {
		set nofill 3
	    } else {
		set nofill 2
	    }
	} elseif {$inlist} {
	    # end of list
	    set inlist 0
	    lappend newmsg ".PP"
	}
	set first [string index $line 0]
	if {$first == "'"} {
	    set line "\\$line"
	} elseif {$first == ""} {
	    set line ".PP"
	}
	if {$nofill > 2} {
	    set nofill 2
	    lappend newmsg ".nf"
	} elseif {$nofill == 1} {
	    lappend newmsg ".fi"
	}
	lappend newmsg $line
    }
    if {$indented} {
	lappend newmsg ".RE $indentlevel"
    }
    return $newmsg
}
