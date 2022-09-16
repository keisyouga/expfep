#
# expfep
#
# fep using expect
#
# termcap notes
# =============
#   - save current cursor position
#     sc
#   - restore cursor position
#     rc
#   - begin reverse video
#     rev
#   - end reverse video
#     sgr0
#   - begin underline
#     smul
#   - end underline
#     rmul
#   - set scroll region
#     scr <line1> <line2>
#     also call stty to set rows
#     stty rows <line2 - line1 + 1>
#   - cursor down n line
#     cud <n>
#   - custom up n line
#     cuu <n>>



# add directory lib to auto_path
set script_dir [file dirname [file normalize [info script]]]
lappend ::auto_path [file join $script_dir lib]

# save current directory
set orig_dir [pwd]
# work_dir; config.tcl, dic, map are in this directory
set work_dir [file dirname $script_dir]
cd $work_dir

set ::APP_NAME "expfep"
set ::VERSION 0.1

################################################################
package require Expect

proc run_tput args {
	puts -nonewline [exec tput {*}$args]
	flush stdout
}

# update screen
# call this procedure after handle user input
proc show {} {
	global fep_info cands

	################
	# cands line
	if {!$fep_info(enabled)} {
		# off state
		show_msg $::config(menu_off_text)
	} elseif {$cands(str) eq ""} {
		# show fep status
		set a [exec tput rev]
		set b [exec tput sgr0]
		show_msg $::config(menu_on_text)
	} else {
		# show cands
		show_cands
	}

	################
	# cursor line
	# erase previous precommit
	# puts previous precommit in background color
	if {$fep_info(precommit_old) ne ""} {
		run_tput sc
		run_tput setaf 0
		exp_send_user -- $fep_info(precommit_old)
		run_tput sgr0
		run_tput rc
		set fep_info(precommit_old) ""
	}
	# show precommit
	if {$fep_info(precommit) ne ""} {
		show_precommit
	}
}

# load dic from file
proc load_dicfile {filename} {
	global fep_info dic

	set fep_info(dicfile) $filename

	# because duplicate keys, we can not use dict(3tcl)
	set dic(key) {}
	set dic(data) {}

	if {$filename eq ""} {
		return
	}

	if {[catch {set chan [open $filename]} fid]} {
		exp_send_error "error: open $filename\n"
		return
	}
	fconfigure $chan -encoding utf-8


	while {[gets $chan line] >= 0} {
		set fields [split $line]
		lappend dic(key) [lindex $fields 0]
		lappend dic(data) [join [lrange $fields 1 end]]
	}
	close $chan

	set fep_info(dicfile) $filename
}

# load mapping from file
proc load_mapfile {filename} {
	global fep_info

	set fep_info(mapfile) ""
	set fep_info(mapping) {}

	if {$filename eq ""} {
		return
	}

	if {[catch {set chan [open $filename]} fid]} {
		exp_send_error "error: open $filename\n"
		return
	}
	fconfigure $chan -encoding utf-8

	while {[gets $chan line] >= 0} {
		set fields [split $line]
		lappend fep_info(mapping) [lindex $fields 0]
		lappend fep_info(mapping) [join [lrange $fields 1 end]]
	}
	close $chan

	set fep_info(mapfile) $filename
}

# reduce one line scroll region for cands line
proc reset_screen {} {

	global spawn_out
	set lines [exec tput lines]
	set newlines [expr $lines - 1]
	set cols [exec tput cols]

	# `exp_stty row' signals sigwinch, so disable handler temporary
	trap {SIG_IGN} SIGWINCH
	exp_stty rows $newlines

	# make lines and columns of child's tty same as parent's
	if {[info exist spawn_out(slave,name)]} {
		exp_stty rows $newlines < $spawn_out(slave,name)
		exp_stty columns $cols < $spawn_out(slave,name)
	} else {
		# spawn_out not exist
	}

	# set scroll region
	run_tput sc
	run_tput csr 0 [expr $newlines - 1]
	run_tput rc

	# cursor one line down, one line up
	# make sure that cursor places in scroll region
	run_tput cud 1
	run_tput cuu 1

	# enable handler
	trap {sigwinch_handler} SIGWINCH
}

proc sigwinch_handler {} {
	# puts "sigwinch_handler"
	reset_screen
}

proc myinit {} {

	reset_screen

	# initial fep mode
	change_fep_mode "skk-jisyo" "map/ja-hiragana.map" "dic/skk-jisyo.dic"

	trap {sigwinch_handler} SIGWINCH

	if {[file exist "config.tcl"]} {
		source "config.tcl"
	}

	show
}

# restore terminal settings when the program exits
proc cleanup {} {
	set lines [exec tput lines]
	set newlines [expr $lines + 1]

	# clear cands line
	run_tput sc
	run_tput cup $lines
	run_tput ed
	run_tput rc

	# restore terminal setting
	trap {SIG_DFL} SIGWINCH
	exp_stty rows $newlines

	run_tput sc
	run_tput csr 0 [expr $newlines - 1]
	run_tput rc
}

# spawn program to interact with
proc myspawn {} {
	# spawn_id, spawn_out must be global
	global spawn_id spawn_out
	global program work_dir orig_dir

	# spawn new process in orig_dir
	cd $orig_dir
	exp_spawn {*}$program

	# back to work_dir for load_mapfile, load_dicfile
	cd $work_dir
}

# show message in last line
proc show_msg {msg} {
	set lines [exec tput lines]

	run_tput sc
	run_tput cup $lines
	run_tput el
	exp_send_user -- "$msg"
	run_tput rc
	#sleep 0.1
}

# show precommit in cursor position
proc show_precommit {} {
	global fep_info

	# make underline
	run_tput sc
	run_tput smul
	exp_send_user -- $fep_info(precommit)
	run_tput rmul
	run_tput rc

	# store previous precommit
	set fep_info(precommit_old) $fep_info(precommit)
}

# TODO: check COLUMNS when display cands
# call exp_send_user once?
proc show_cands {} {
	global cands

	set lines [exec tput lines]

	# save current cursor position and move to cands line
	run_tput sc
	run_tput cup $lines
	run_tput el

	set ncands [llength $cands(str)]
	set current_page [expr $cands(pos) / $cands(item_in_page_max)]

	set begin [expr $current_page * $cands(item_in_page_max)]
	set end [expr min($ncands, $begin + $cands(item_in_page_max))]
	for {set i $begin} {$i < $end} {incr i} {
		# highlight current selected item
		if {$i == $cands(pos)} {
			#run_tput smso
			run_tput rev
			#run_tput dim
		}
		#exp_send_user -- [get_cands $i]
		exp_send_user -- "[join [lindex $cands(str) $i] :] "
		# restore highlight
		if {$i == $cands(pos)} {
			#run_tput rmso
			run_tput sgr0
		}
	}

	exp_send_user -- "[expr 1 + $cands(pos)]/$ncands"

	# restore cursor position
	run_tput rc
}

# become no keyseq state
proc clear {} {
	global fep_info cands
	set fep_info(precommit) ""
	#set fep_info(precommit_old) ""
	set fep_info(keyseq) ""
	set fep_info(mapped) ""
	set cands(str) ""
	set cands(pos) 0
}

# remove last 1 char in keyseq
proc keyseq_op_backspace {} {
	global fep_info

	set fep_info(keyseq) [lrange $fep_info(keyseq) 0 end-1]
	if {[has_keyseq?]} {
		do_graph
	} else {
		clear
	}
}

proc has_keyseq? {} {
	global fep_info
	if {[llength $fep_info(keyseq)] > 0} {
		return 1
	} else {
		return 0
	}
}

# process clear key or commit key or backspace key
# return 0 if do nothing
proc keyseq_op {data} {
	# key used when keyseq is present
	if {![has_keyseq?]} {
		return 0
	}

	switch -exact -- $data {
		"" {
			clear
		} " " {
			commit
		} "" {
			keyseq_op_backspace
		} default {
			return 0
		}
	}
	return 1
}

# convert keyseq to precommit using mapping
proc do_map {} {
	global fep_info

	set str [join $fep_info(keyseq) ""]
	set mapped [string map $fep_info(mapping) $str]
	set fep_info(precommit) $mapped
}

# create cands from precommit using dic, update precommit
proc do_dic {} {
	global fep_info cands dic

	set matched [lsearch -all -glob $dic(key) $fep_info(precommit)]
	set cands(str) {}
	foreach i $matched {
		lappend cands(str) "[lindex $dic(key) $i] [lindex $dic(data) $i]"
	}
	if {[llength $cands(str)] > 0} {
		set cands(pos) 0
		set fep_info(precommit) [lindex $cands(str) $cands(pos) 1]
	}

	return
}

# commit precommit and clear
proc commit {} {
	global fep_info
	exp_send -- $fep_info(precommit)
	set fep_info(precommit_old) ""
	clear
}

proc use_mapping? {} {
	global fep_info
	if {$fep_info(mapping) ne ""} {
		return 1
	}
	return 0
}

proc use_dic? {} {
	global dic
	if {$dic(key) ne ""} {
		return 1
	}
	return 0
}

# keyseq => [do_map] => [do_dic] => precommit
proc do_graph {} {
	global fep_info

	if {[use_mapping?]} {
		do_map
	} else {
		set fep_info(precommit) [join $fep_info(keyseq) ""]
	}

	if {[use_dic?]} {
		do_dic
	} else {
		# commit when precommit is modified in do_map
		if {[join $fep_info(keyseq) ""] ne $fep_info(precommit)} {
			commit
		}
	}
}

# append graph_key to keyseq
# return 0 if do nothing
proc keyseq_append {data} {
	global fep_info
	if {[regexp -- {^[[:graph:]][[:graph:]]*$} $data]} {
		lappend fep_info(keyseq) $data
		return 1
	}
	return 0
}

# name of fepmode, mapfile, dicfile
proc change_fep_mode {name map dic} {
	global fep_info
	load_mapfile $map
	load_dicfile $dic
	set fep_info(mode) $name
}

# load dic, map by key
# return 0 if do nothing
proc manage_fep {data} {
	global fep_info dic
	switch -exact -- $data "\0331" {
		# ESC-1
		eval $::config(set_mode1)
	} "\0332" {
		# ESC-2
		eval $::config(set_mode2)
	} "\0333" {
		# ESC-3
		eval $::config(set_mode3)
	} "\0334" {
		# ESC-4
		eval $::config(set_mode4)
	} default {
		return 0
	}

	do_graph
	return 1
}

# commit cand
# 0-9 key is used for commit by number
# return 0 if do nothing
proc cands_commit {data} {
	global fep_info cands

	if {![string match {[0-9]} $data]} {
		return 0
	}

	set page_first [expr $cands(pos) - $cands(pos) % $cands(item_in_page_max)]
	# assumes $data is number from 0 to 9
	# convert 1,2,3,4,5,6,7,8,9,0 => 0,1,2,3,4,5,6,7,8,9
	set n [expr ($data - 1) % 10]
	set cands(pos) [expr $page_first + $n]

	set fep_info(precommit) [lindex $cands(str) $cands(pos) 1]
	commit
	return 1
}

# change cand selection
# return 0 if do nothing
proc cands_op {data} {
	global cands fep_info
	switch -exact -- $data "" {
		incr cands(pos) 1
	} "" {
		incr cands(pos) -1
	} "" {
		incr cands(pos) $cands(item_in_page_max)
	} "" {
		incr cands(pos) -$cands(item_in_page_max)
	} "" {
		set cands(pos) 0
	} "" {
		set cands(pos) [expr [llength $cands(str)] - 1]
	} default {
		return 0
	}
	# make sure cands(pos) is in valid range
	set cands(pos) [expr $cands(pos) % [llength $cands(str)]]

	set fep_info(precommit) [lindex $cands(str) $cands(pos) 1]
	return 1
}

proc has_cands? {} {
	global cands
	return [expr [llength $cands(str)] > 0]
}

proc interact_fep_on {} {
	global fep_info

	# puts "interact_fep_on: begin"
	interact {
		$::config(active_key) {
			set fep_info(enabled) 0
			clear
			return
		}
		-re {[0-9]} {
			if {[has_cands?]} {
				if {[cands_op $interact_out(0,string)]} {
					return
				}
				if {[cands_commit $interact_out(0,string)]} {
					return
				}
			}
			exp_send -- $interact_out(0,string)
		}
		-re {[ ]} {
			if {[keyseq_op $interact_out(0,string)]} {
				return
			}
			exp_send -- $interact_out(0,string)
		}
		-re {[[:graph:]]} {
			if {[keyseq_append $interact_out(0,string)]} {
				do_graph
				return
			}
			exp_send -- $interact_out(0,string)
		}
		-re {\033[1234]} {
			# ESC-1, ESC-2, ESC-3, ESC-4
			# used for manage fep key
			if {[manage_fep $interact_out(0,string)]} {
				return
			}
			# send to current process
			exp_send -- $interact_out(0,string)
		}
		-re {\033\[.*} {
			# CSI sequence
			# send to current process
			exp_send -- $interact_out(0,string)
		}
		-re {\033O.*} {
			# SS3 sequence
			# send to current process
			exp_send -- $interact_out(0,string)
		}
		-re {\033.} {
			# rest of ESC-keys
			# send to current process
			exp_send -- $interact_out(0,string)
		}
	}
	# puts "interact_fep_on: end"
}

proc interact_fep_off {} {
	global fep_info

	# puts "interact_fep_off: begin"
	interact {
		$::config(active_key) {
			set fep_info(enabled) 1
			return
		}
	}
	# puts "interact_fep_off: end"
}

# send all keyboard event to handler
proc myloop {} {
	global fep_info
	while {![eof $::spawn_id]} {
		if {$fep_info(enabled)} {
			interact_fep_on
		} else {
			interact_fep_off
		}
		show
	}
}

proc usage {} {
	puts "usage: $::argv0 \[options\] \[-e command args\]"
	exit
}

proc version {} {
	puts "$::APP_NAME $::VERSION"
	exit
}

################
# global variables
################

# spawn this program
set program /bin/sh
catch {set program $env(SHELL)}

# fep_info array
#   mode : fep mode name
#   enabled : 1 if enabled, 0 if disabled
#   precommit : string commited by commit key
#   precommit_old : previously displayed precommit string
#   keyseq : store key sequence
#   mapping : using mapping to convert keyseq
#   mapfile : currently loaded map file
#   dicfile : currently loaded dic file
array set fep_info {
	mode ""
	enabled 0
	precommit ""
	precommit_old ""
	keyseq ""
	mapping ""
	mapfile ""
	dicfile ""
}

# cands array
#   str : cands string {key1 data1 key2 data2 ...} set by do_dic
#   pos : selected cand position
#   item_in_page_max : max number to show cands in one page
array set cands {
	str {}
	pos 0
	item_in_page_max 4
}

# dictionary key and data
array set dic {
	key {}
	data {}
}

# default config
array set config {
	active_key ""
	menu_off_text "^O: Enable FEP"
	menu_on_text "^O: Disable FEP M-Number: Switch Mode"
	set_mode1 {change_fep_mode "hiragana" "map/ja-hiragana.map" ""}
	set_mode2 {change_fep_mode "katakana" "map/ja-katakana.map" ""}
	set_mode3 {change_fep_mode "cangjie" "" "dic/cangjie35-jis.dic"}
	set_mode4 {change_fep_mode "skk-jisyo" "map/ja-hiragana.map" "dic/skk-jisyo.dic"}
}

################
# log file
################

# log_file "$argv0.log"

################
# program start
################

# show usage
if {[regexp -- {^--?h} $argv]} {
	usage
}

# show version
if {[regexp -- {^--?v} $argv]} {
	version
}

# set program by command line
for {set i 0} {$i < $argc} {incr i} {
	# after "-e" is spawned as program
	if {[lindex $argv $i] eq "-e"} {
		set program [lrange $argv [expr $i + 1] end]
	}
	# puts program=<$program>
}

myinit

myspawn

myloop

cleanup
