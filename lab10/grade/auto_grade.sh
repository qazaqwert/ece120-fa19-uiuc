#!/bin/bash

# Autograde part. It first creates script file for 'lc3-grade' and object files 
# for test cases. It then creates a local copy of student's '${lab}.bin' file
# and then executes automatic part of grading using 'lc3-grade'. It then appends to
# '{gradefile}' extra information needed for manually grading.
#
# Usage: auto_grade.sh roster

function main {
    # File config defines variable 'svnpath' and 'binpath'
    # If the first command succeeds the second will never be executed
    source ../../scripts/config || { echo >&2 "Please cd into the directory first"; exit 1; }
    lab=lab10
    case_folder=cases
    lc3script=auto_grade.lc3-grade

    # Check if help was requested
    if [ "$1" = "help" ]
    then
        give_help
    fi

    # Check if number of arguments is correct
    if [ $# -ne 1 ]; then 
        echo Usage: $0 roster
        exit
    fi

    # Parse arguments
    roster=${svnpath}/_rosters/$1.txt

    # Check for valid roster file
    if [ ! -f ${roster} ]
    then
        echo "Invalid file: \"${roster}\""
        exit
    fi

    # Create file auto_grade.lc3-grade
    create_lc3script > ${lc3script}

    # Create object files, make output silent
    for testcase in `ls ${case_folder}/`
    do
        lc3convert ${case_folder}/${testcase} > /dev/null
    done

    echo "Running grading script for ${lab} in ${svnpath}"

    for student in `cat $roster`
    do
        # Check student has a directory, otherwise continue to next student
        if [ ! -d ${svnpath}/${student}/${lab} ]
        then
            continue;
        fi

        # Add extra space to make sure previous line gets completely erased
        echo -ne " ${student}     \r"

        gradefile=${svnpath}/${student}/${lab}/grade.txt
        lab_bin=${svnpath}/${student}/${lab}/${lab}.bin

        # Make sure ${gradefile} does not exist
        if [ -f ${gradefile} ]
        then
            rm ${gradefile}
        fi

        # Check student has file, otherwise continue to next student
        if [ ! -f ${lab_bin} ]
        then
            echo "File \"${lab}.bin\" does not exist" > ${gradefile}
            echo "Total: 0/100" >> ${gradefile}
            continue
        fi

        # Check file was modified, otherwise continue to next student
        if [ "`wc ${lab_bin} | awk '{print $1}'`" -le "`wc ../distro/${lab}.bin | awk '{print $1}'`" ]
        then
            echo "File \"${lab}.bin\" was not modified" > ${gradefile}
            echo "Total: 0/100" >> ${gradefile}
            continue
        fi

        # Make local copy of file, it will be cleaned up later
        cp ${lab_bin} ${lab}_student.bin

        # Assemble code
        echo "lc3convert output:" > ${gradefile}
        lc3convert ${lab}_student.bin &>> ${gradefile}
        echo >> ${gradefile}

        # Run lc3-grade
        timeout 200 ${binpath}/lc3-grade ${lc3script} ${gradefile}

        # lc3-grade uses timeout when running, so this is probably useless
        # Exit status is 124 if command times out
        # CAUTION: ${binpath}/timeout is not the same as Linux's timeout
        # exit status for ${binpath}/timeout is 255 instead
        if [ "$?" -eq 124 ]
        then
            echo >> ${gradefile}
            echo "Infinite loop detected!" >> ${gradefile}
            echo >> ${gradefile}
        fi

        # Search for line starting with the word 'total', ignore case
        grade=`grep -i ^Total ${gradefile} | awk '{print $2}'`
        # Remove from the grade the trailing part
        grade=${grade%/*}

        # Remove last line (with total)
        sed -i '$ d' ${gradefile}

        # Check for proper halt pattern "1111 0000 0010 0101", ignore extra spaces
        if [ `grep -ce "1\s*1\s*1\s*1\s*0\s*0\s*0\s*0\s*0\s*0\s*1\s*0\s*0\s*1\s*0\s*1" ${lab}_student.bin` -gt 0 ]
        then
            echo "Proper halt: 5/5" >> ${gradefile} 
            ((grade += 5))
        else
            echo "Proper halt: 0/5" >> ${gradefile} 
        fi

        # Check for proper start pattern "0011 0001 0000 0000", ignore extra spaces
        if [ `grep -ce "0\s*0\s*1\s*1\s*0\s*0\s*0\s*1\s*0\s*0\s*0\s*0\s*0\s*0\s*0\s*0" ${lab}_student.bin` -gt 0 ]
        then
            echo "Program starts at x3100: 5/5" >> ${gradefile} 
            ((grade += 5))
        else
            echo "Program starts at x3100: 0/5" >> ${gradefile} 
        fi

        # If all went fine, award 5 extra points
        if [ "$grade" -eq 65 ]
        then
            echo "Program reads 10 consecutive numbers starting from addr x3132: 5/5" >> ${gradefile}
            ((grade += 5))
        else
            echo "Program reads 10 consecutive numbers starting from addr x3132: 0/5" >> ${gradefile}
        fi

        echo "Functionality Total: ${grade}/70" >> ${gradefile}
        echo >> ${gradefile}

        # Manually grade style
        echo "Uses one loop: /5" >> ${gradefile}
        echo "Uses one test to compare numbers: /5" >> ${gradefile}
        echo "No unnecessary data movement: /5" >> ${gradefile}
        echo "Code is within reasonable limit: /5" >> ${gradefile}
        echo "Style Total: /20" >> ${gradefile}
        echo >> ${gradefile}

        # Manually grade comments
        echo "Lines are < 120 chars: /2" >> ${gradefile}
        echo "Machine code and comments are formatted properly: /3" >> ${gradefile}
        echo "Introductory paragraph on solution: /2" >> ${gradefile}
        echo "Well-commented: /3" >> ${gradefile}
        echo "Format Total: /10" >> ${gradefile}
        echo >> ${gradefile}

        echo "Other deductions: " >> ${gradefile}

        echo >> ${gradefile}
        echo "Total: /100" >> ${gradefile}
    done

    # Clean up
    rm ${lc3script} ${case_folder}/*.obj ${lab}_student.bin ${lab}_student.obj
}

function create_lc3script {
    # Create script file for lc3-grade. Make sure that there's no whitespace
    # in front of the terminating EOF, otherwise it will not be recognized
cat << EOF
test positive_min_max 5
    load ${lab}_student
    load ${case_folder}/numbers1
    set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
    run x3100 halt
    expect reg r5 x03FF
end

test positive_max_min 5
    load ${lab}_student
    load ${case_folder}/numbers2
    set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
    run x3100 halt
    expect reg r5 x03FF
end

test positive_random 5
    load ${lab}_student
    load ${case_folder}/numbers3
    set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
    run x3100 halt
    expect reg r5 x1978
end

test negative_max_min 5
	load ${lab}_student
	load ${case_folder}/numbers4
    set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x0000
end

test negative_min_max 5
	load ${lab}_student
	load ${case_folder}/numbers5
	set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x0000
end

test negative_random 5
	load ${lab}_student
	load ${case_folder}/numbers6
	set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x0000
end

test mixed_min_max 5
	load ${lab}_student
	load ${case_folder}/numbers7
	set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x0296
end

test mixed_max_min 5
	load ${lab}_student
	load ${case_folder}/numbers8
	set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x052D
end

test mixed_random 5
	load ${lab}_student
	load ${case_folder}/numbers9
    set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
    set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x9EC6
end

test result_in_R5 5
	load ${lab}_student
	load ${case_folder}/numbers1
	set reg r0 x0000 r1 x0000 r2 x0000 r3 x0000
	set reg r4 x0000 r5 x0000 r6 x0000 r7 x0000
	run x3100 halt
	expect reg r5 x03FF
end

test reg_initialization 5
    load ${lab}_student
    load ${case_folder}/numbers3
    set reg r0 xFFFF r1 xFFFF r2 xFFFF r3 xFFFF
    set reg r4 xFFFF r5 xFFFF r6 xFFFF r7 xFFFF
    run x3100 halt
    expect reg r5 x1978
end
EOF
}

function give_help {
    # More info on: http://en.wikipedia.org/wiki/Here_document#Unix-Shells
    # E.g: http://stackoverflow.com/questions/2500436/how-does-cat-eof-work-in-bash
    # This type of redirection instructs the shell to read input from the 
    # current source until a line containing only 'delimiter' (with no trailing 
    # blanks) is seen.
    #
    # All of the lines read up to that point are then used as the standard input
    # for a command.
    #
    # The format of here-documents is:
    #
    #          <<[-]delimiter
    #                  here-document
    #          delimiter
    #
    # If the redirection operator is <<-, then all leading tab characters are 
    # stripped from input lines and the line containing delimiter. This allows 
    # here-documents within shell scripts to be indented in a natural fashion.
cat <<- EOF
# Autograde part. It first creates script file for 'lc3-grade' and object files 
# for test cases. It then creates a local copy of student's '${lab}.bin' file
# and then executes automatic part of grading using 'lc3-grade'. It then appends to
# '{gradefile}' extra information needed for manually grading.
#
# Usage: auto_grade.sh roster
EOF
    exit
}

# By passing "$@" to main() you can access the command-line arguments $1, $2, 
# et al just as you normally would
main "$@"

