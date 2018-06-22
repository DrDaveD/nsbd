# take a GNU GPL COPYING file and make a tcl proc out of it
# Written by Dave Dykstra <dwd@bell-labs.com> 1 May 1997
BEGIN{
    print "# generated by lic2tcl.awk"
    print "set licenseTxt {"
    n = 0
}
/GNU GENERAL PUBLIC LICENSE/{
    n = n + 1
}
/\014/{
    if (n == 2) {
	# on form feeds, split into separate tcl command to avoid
	#   messages about strings being too long in tcl2c
	print "}"
	print "append licenseTxt {"
    }
}
!/\014/{
    if (n == 2) print
}
/END OF TERMS/{
    print "}"
    print "proc getLicense {} {"
    print "    global licenseTxt"
    print "    return $licenseTxt"
    print "}"
    exit
}