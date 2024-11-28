#!/bin/sh
#
# Copyright (c) 2024, Jesús Daniel Colmenares Oviedo <DtxdF@disroot.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

DEFAULT_CONFIG="%%PREFIX%%/share/littlejet/files/default.conf"

. "${DEFAULT_CONFIG}"

# User's configuration file.
CONFIGDIR="${HOMEDIR}/.config/littlejet"
CONFIG="${CONFIGDIR}/config.conf"

main()
{
    local command
    command="$1"

    local lib_subr
    lib_subr="${LIB_SUBR}"

    if [ ! -f "${lib_subr}" ]; then
        echo "${lib_subr}: library cannot be found." >&2
        exit 66 # EX_NOINPUT
    fi
    
    . "${lib_subr}"

    if [ ! -f "${CONFIG}" ]; then
        debug "Creating user configuration file '${CONFIG}'"

        safe_exc mkdir -p -- "${CONFIGDIR}"
        safe_exc cp -- "${FILESDIR}/user.conf" "${CONFIGDIR}/config.conf"
        safe_exc chown ${UID}:${UID} "${CONFIGDIR}/config.conf"
        safe_exc chmod 640 "${CONFIGDIR}/config.conf"
    fi

    . "${CONFIG}"

    atexit_init
    atexit_add ". \"${DEFAULT_CONFIG}\""
    atexit_add ". \"${CONFIG}\""
    atexit_add ". \"${lib_subr}\""
    atexit_add "kill_proc_tree $$"

    shift

    case "${command}" in
        add-label|add-node|copy|copy-nodes|create|del-label|del-labels|del-node|del-nodes|destroy) ;&
        get-label|get-labels|get-nodes|get-projects|rename|run-appjail|run-cmd|run-director) ;&
        run-script|schedule|set-director|set-env|show|usage|version) littlejet_${command} "$@" ;;
        *) littlejet_usage; exit ${EX_USAGE} ;;
    esac
}

littlejet_add-label()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local node
    node="$2"

    _basic_node_checks "${project}" "${node}"

    shift 2

    if [ $# -eq 0 ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    local labeldir="${NODESDIR}/${project}/${node}/labels"

    if [ ! -d "${labeldir}" ]; then
        debug "Creating '${labeldir}'"
        safe_exc mkdir -p -- "${labeldir}"
    fi
    
    local label
    for label in "$@"; do
        if ! checklabelsyntax "${label}"; then
            err "${label}: invalid label syntax."
            exit ${EX_DATAERR}
        fi

        debug "Writing label '${label}'"

        local name
        name=`printf "%s" "${label}" | cut -d= -f1`

        local value
        value=`printf "%s" "${label}" | cut -d= -f2-`

        printf "%s\n" "${value}" > "${labeldir}/${name}"
    done

    return ${EX_OK}
}

littlejet_copy()
{
    local _o
    local opt_force=false
    local opt_transfer_nodes=true

    while getopts ":fN" _o; do
        case "${_o}" in
            f)
                opt_force=true
                ;;
            N)
                opt_transfer_nodes=false
                ;;
            *)
                littlejet_usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local new_project
    new_project="$2"

    local extra_args=

    if ${opt_force}; then
        extra_args="-f"
    fi

    littlejet_create ${extra_args} \
        "${new_project}" "${PROJECTSDIR}/${project}/appjail-director.yml"

    if ${opt_transfer_nodes}; then
        littlejet_copy-nodes -O "${project}" "${new_project}"
    fi

    return ${EX_OK}
}

littlejet_copy-nodes()
{
    local _o
    local opt_overwrite=false

    while getopts ":O" _o; do
        case "${_o}" in
            O)
                opt_overwrite=true
                ;;
            *)
                littlejet_usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    local src_project
    src_project="$1"

    _basic_project_checks "${src_project}"
    _exit_if_dirty "${src_project}"

    local dst_project
    dst_project="$2"

    _basic_project_checks "${dst_project}"
    _exit_if_dirty "${dst_project}"

    local node
    node="$3"

    local src_nodesdir
    src_nodesdir="${NODESDIR}/${src_project}"

    local dst_nodesdir
    dst_nodesdir="${NODESDIR}/${dst_project}"

    if ${opt_overwrite}; then
        if [ -d "${dst_nodesdir}" ]; then
            safe_exc rm -rf -- "${dst_nodesdir}"
        fi
    fi

    if [ -n "${node}" ]; then
        _basic_node_checks "${src_project}" "${node}"

        local src_nodedir
        src_nodedir="${src_nodesdir}/${node}"

        if [ ! -d "${dst_nodesdir}" ]; then
            safe_exc mkdir -p -- "${dst_nodesdir}"
        fi

        local dst_nodedir
        dst_nodedir="${dst_nodesdir}/${node}"

        safe_exc cp -a -- "${src_nodedir}" "${dst_nodedir}"
    else
        if [ -d "${src_nodesdir}" ]; then
            safe_exc cp -a -- "${src_nodesdir}" "${dst_nodesdir}"
        else
            warn "No nodes have been added."
        fi
    fi

    return ${EX_OK}
}

littlejet_add-node()
{
    local _o
    local opt_test=true

    while getopts ":T" _o; do
        case "${_o}" in
            T)
                opt_test=false
                ;;
            *)
                littlejet_usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local node
    node="$2"

    if [ -z "${node}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if ! checknodename "${node}"; then
        err "${node}: invalid node name."
        exit ${EX_DATAERR}
    fi

    local nodedir="${NODESDIR}/${project}/${node}"

    if [ -d "${nodedir}" ]; then
        err "${node}: node already added."
        exit ${EX_CANTCREAT}
    fi

    if ${opt_test}; then
        local errlevel

        local output
        output=`testnode "${node}" 2>&1`
        
        errlevel=$?

        if [ ${errlevel} -ne 0 ]; then
            err "Could not add node '${node}': ${output}"
            exit ${EX_NOPERM}
        fi
    fi

    debug "Creating new node '${node}'"

    debug "Creating '${nodedir}'"
    safe_exc mkdir -p -- "${nodedir}"

    return ${EX_OK}
}

littlejet_create()
{
    local _o
    local opt_force=false

    while getopts ":f" _o; do
        case "${_o}" in
            f)
                opt_force=true
                ;;
            *)
                littlejet_usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    local project
    project="$1"

    if [ -z "${project}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if ! checkprojectname "${project}"; then
        err "${project}: invalid project name."
        exit ${EX_DATAERR}
    fi

    local projectdir
    projectdir="${PROJECTSDIR}/${project}"

    local done_file
    done_file="${projectdir}/.done"

    if ! ${opt_force} && [ -f "${done_file}" ]; then
        err "${project}: project already created."
        exit ${EX_CANTCREAT}
    fi

    # Remove dirty project.
    if ! ${opt_force} && [ -d "${projectdir}" ]; then
        debug "${project}: removing dirty project"
        safe_exc rm -rf -- "${projectdir}"
    fi

    local director_file
    director_file="${2:-appjail-director.yml}"

    if [ ! -f "${director_file}" ]; then
        err "${director_file}: project file not found."
        exit ${EX_NOINPUT}
    fi

    local workdir
    workdir=`dirname -- "${director_file}"`

    debug "Cloning '${workdir}' as '${projectdir}'"
    safe_exc mkdir -p -- "${projectdir}"
    (cd "${workdir}"; mirror . "${projectdir}") || exit $?

    local director_file_bs
    director_file_bs=`safe_exc basename -- "${director_file}"` || exit $?

    if [ "${director_file_bs}" != "appjail-director.yml" ]; then
        debug "Director filename '${director_file_bs}' is different than 'appjail-director.yml'"
        safe_exc mv -- "${projectdir}/${director_file_bs}" "${projectdir}/appjail-director.yml"
        debug "Changed: '${director_file_bs}' -> 'appjail-director.yml' in '${projectdir}'"
    fi

    safe_exc touch -- "${done_file}"

    debug "Done: ${project}"

    return ${EX_OK}
}

littlejet_del-label()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local node
    node="$2"

    _basic_node_checks "${project}" "${node}"

    local label
    label="$3"

    _basic_label_checks "${project}" "${node}" "${label}"

    local labelfile
    labelfile="${NODESDIR}/${project}/${node}/labels/${label}"

    safe_exc rm -rf -- "${labelfile}"

    return ${EX_OK}
}

littlejet_del-labels()
{
    local project
    project="$1"

    local node
    node="$2"

    local labels
    labels=`littlejet_get-labels "${project}" "${node}"` || exit $?

    local label
    for label in ${labels}; do
        littlejet_del-label "${project}" "${node}" "${label}"
    done

    return ${EX_OK}
}

littlejet_del-node()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local node
    node="$2"

    _basic_node_checks "${project}" "${node}"

    destroy "${project}" "${node}"

    debug "${node}: deleting node"

    local nodedir
    nodedir="${NODESDIR}/${project}/${node}"

    safe_exc rm -rf -- "${nodedir}"

    return ${EX_OK}
}

littlejet_del-nodes()
{
    local project
    project="$1"

    local nodes
    nodes=`littlejet_get-nodes "${project}"` || exit $?

    if [ -n "${nodes}" ]; then
        warn "Destroying all nodes of '${project}'"

        local output
        output=`tempdir` || exit $?

        atexit_add "removedir \"${output}\""

        local nproc=0

        local node
        for node in ${nodes}; do
            littlejet_del-node "${project}" "${node}" > "${output}/${node}.out" 2>&1 &

            atexit_add "safe_kill $! $$"

            nproc=$((nproc+1))

            local errlevel

            debug "Job:${nproc}, Total:${NCPU}"

            test "${nproc}" -ge "${NCPU}"

            errlevel=$?

            if [ ${errlevel} -eq 0 ]; then
                debug "Waiting for '${nproc}' jobs"

                nproc=0

                wait || exit $?
            elif [ ${errlevel} -eq 1 ]; then
                continue
            else
                err "Incorrect value for parameter 'NCPU'"
                exit ${EX_CONFIG}
            fi
        done

        wait || exit $?

        for node in ${nodes}; do
            local outfile
            outfile="${output}/${node}.out"

            if [ -f "${outfile}" ]; then
                info "[project:${project} / node:${node}]:"

                cat -- "${outfile}"
            fi
        done

        removedir "${output}"
    fi

    return ${EX_OK}
}

littlejet_run-script()
{
    local project=

    while getopts ":p:" _o; do
        case "${_o}" in
            p)
                project="${OPTARG}"
                ;;
            *)
                littlejet_usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    local script
    script="$1"

    if [ -z "${script}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    shift

    if ! checkscriptname "${script}"; then
        err "${script}: invalid RunScript name."
        exit ${EX_DATAERR}
    fi

    local projects

    if [ -n "${project}" ]; then
        projects="${project}"
    else
        projects=`littlejet_get-projects` || exit $?
    fi

    local script_pathname
    script_pathname=`getscript "${script}"`

    if [ $? -ne 0 ]; then
        err "Error finding RunScript '${script}'"
        exit ${EX_NOINPUT}
    fi

    for project in ${projects}; do
        export LITTLEJET_PROJECT="${project}"
        export LITTLEJET_DEFAULT_CONFIG="${DEFAULT_CONFIG}"
        export LITTLEJET_USER_CONFIG="${CONFIG}"
        export LITTLEJET_LIB_SUBR="${LIB_SUBR}"

        local errlevel

        "${script_pathname}" "$@"

        errlevel=$?

        if [ ${errlevel} -ne 0 ]; then
            exit ${errlevel}
        fi
    done

    return ${EX_OK}
}

littlejet_destroy()
{
    local project
    project="$1"

    _basic_project_checks "${project}"

    littlejet_del-nodes "${project}"

    warn "Destroying project '${project}' locally"

    local projectdir
    projectdir="${PROJECTSDIR}/${project}"

    safe_exc rm -rf -- "${projectdir}"

    local nodesdir
    nodesdir="${NODESDIR}/${project}"

    if [ -d "${nodesdir}" ]; then
        warn "Destroying nodes of '${project}' locally"

        safe_exc rm -rf -- "${nodesdir}"
    fi

    return ${EX_OK}
}

littlejet_get-label()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local node
    node="$2"

    _basic_node_checks "${project}" "${node}"

    local label
    label="$3"

    _basic_label_checks "${project}" "${node}" "${label}"

    local labelfile
    labelfile="${NODESDIR}/${project}/${node}/labels/${label}"

    safe_exc head -1 -- "${labelfile}"

    return ${EX_OK}
}

littlejet_get-labels()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local node="$2"

    _basic_node_checks "${project}" "${node}"

    local labelsdir="${NODESDIR}/${project}/${node}/labels"

    _list_files "${labelsdir}" "No labels have been added."

    return ${EX_OK}
}

littlejet_get-nodes()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local nodesdir
    nodesdir="${NODESDIR}/${project}"

    _list_files "${nodesdir}" "No nodes have been added."

    return ${EX_OK}
}

littlejet_get-projects()
{
    _list_files "${PROJECTSDIR}" "No project has been created."

    return ${EX_OK}
}

_list_files()
{
    local dir
    dir="$1"

    local msg
    msg="$2"

    local nothing=true

    if [ -d "${dir}" ]; then
        local files
        files=`ls -1 -- "${dir}"`

        if [ `ls -1 -- "${dir}" | wc -l` -gt 0 ]; then
            nothing=false

            printf "%s\n" "${files}"
        fi
    fi

    if ${nothing}; then
        warn "${msg}"
    fi
}

littlejet_rename()
{
    local project
    project="$1"

    local new_project
    new_project="$2"

    littlejet_copy "${project}" "${new_project}"

    debug "${project}: removing old project"

    safe_exc rm -rf -- "${PROJECTSDIR}/${project}"

    local nodesdir
    nodesdir="${NODESDIR}/${project}"

    if [ -d "${nodesdir}" ]; then
        debug "${project}: removing old nodes"

        safe_exc rm -rf -- "${NODESDIR}/${project}"
    fi

    return ${EX_OK}
}

littlejet_run-appjail()
{
    _run "appjail" "$@"

    return ${EX_OK}
}

littlejet_run-cmd()
{
    _run "none" "$@"

    return ${EX_OK}
}

littlejet_run-director()
{
    _run "appjail-director" "$@"

    return ${EX_OK}
}

_run()
{
    local target
    target="$1"

    shift

    local _o
    local opt_clean=false
    local opt_header=true
    local opt_parallel=false
    local opt_safe=false
    local project=
    local node=

    while getopts ":CHPsp:n:" _o; do
        case "${_o}" in
            C)
                opt_clean=true
                ;;
            H)
                opt_header=false
                ;;
            P)
                opt_parallel=true
                ;;
            s)
                opt_safe=true
                ;;
            p)
                project="${OPTARG}"
                ;;
            n)
                node="${OPTARG}"
                ;;
            *)
                littlejet_usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ $# -eq 0 ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    local flags=

    if ! ${opt_header}; then
        flags="-H"
    fi

    if ${opt_safe}; then
        flags="${flags} -s"
    fi

    if ${opt_clean}; then
        flags="${flags} -C"
    fi

    local output
    if ${opt_parallel}; then
        if ! checknumber "${NCPU}"; then
            err "Incorrect value for parameter 'NCPU'"
            exit ${EX_CONFIG}
        fi

        output=`tempdir` || exit $?

        atexit_add "removedir \"${output}\""
    fi

    if [ -n "${project}" -a -n "${node}" ]; then
        if ${opt_header}; then
            info "[project:${project} / node:${node}]:"
        fi

        local use_safe_exc="NO"

        if ${opt_safe}; then
            use_safe_exc="YES"
        fi

        local be_dirty="NO"

        if ! ${opt_clean}; then
            be_dirty="YES"
        fi

        case "${target}" in
            appjail-director)
                run_director "${project}" "${node}" "${use_safe_exc}" "${be_dirty}" "$@"
                ;;
            appjail)
                remote_exc "${node}" "${use_safe_exc}" "${be_dirty}" "appjail" "$@"
                ;;
            *)
                remote_exc "${node}" "${use_safe_exc}" "${be_dirty}" "$@"
                ;;
        esac
    elif [ -n "${project}" -a -z "${node}" ]; then
        local nodes
        nodes=`littlejet_get-nodes "${project}"` || exit $?

        local nproc=0

        for node in ${nodes}; do
            if ${opt_parallel}; then
                _run "${target}" ${flags} -p "${project}" -n "${node}" "$@" > "${output}/${node}.out" 2>&1 &

                atexit_add "safe_kill $! $$"

                nproc=$((nproc+1))

                debug "Job:${nproc}, Total:${NCPU}"

                if [ ${nproc} -ge ${NCPU} ]; then
                    debug "Waiting for '${nproc}' jobs"

                    nproc=0

                    wait || exit $?
                fi
            else
                _run "${target}" ${flags} -p "${project}" -n "${node}" "$@"
            fi
        done

        if ${opt_parallel}; then
            wait || exit $?

            for node in ${nodes}; do
                local outfile
                outfile="${output}/${node}.out"

                if [ -f "${outfile}" ]; then
                    cat -- "${outfile}"
                fi
            done

            removedir "${output}"
        fi
    elif [ -z "${project}" -a -n "${node}" ]; then
        local projects
        projects=`littlejet_get-projects` || exit $?

        local nproc=0
        
        for project in ${projects}; do
            if ${opt_parallel}; then
                _run "${target}" ${flags} -p "${project}" -n "${node}" "$@" > "${output}/${project}.out" 2>&1 &

                atexit_add "safe_kill $! $$"

                nproc=$((nproc+1))

                debug "Job:${nproc}, Total:${NCPU}"

                if [ ${nproc} -ge ${NCPU} ]; then
                    debug "Waiting for '${nproc}' jobs"

                    nproc=0

                    wait || exit $?
                fi
            else
                _run "${target}" ${flags} -p "${project}" -n "${node}" "$@"
            fi
        done

        if ${opt_parallel}; then
            wait || exit $?

            for project in ${projects}; do
                local outfile
                outfile="${output}/${project}.out"

                if [ -f "${outfile}" ]; then
                    cat -- "${outfile}"
                fi
            done

            removedir "${output}"
        fi
    else
        local projects
        projects=`littlejet_get-projects`

        local flag_parallel=

        if ${opt_parallel}; then
            flag_parallel="-P"
        fi

        for project in ${projects}; do
            _run "${target}" ${flags} ${flag_parallel} -p "${project}" "$@"
        done
    fi
}

littlejet_set-director()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local director_file
    director_file="$2"

    if [ -z "${director_file}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if [ ! -f "${director_file}" ]; then
        err "${director_file}: project file not found."
        exit ${EX_NOINPUT}
    fi

    safe_exc cp -a -- "${director_file}" "${PROJECTSDIR}/${project}/appjail-director.yml"

    return ${EX_OK}
}

littlejet_set-env()
{
    local project
    project="$1"

    _basic_project_checks "${project}"
    _exit_if_dirty "${project}"

    local env_file
    env_file="$2"

    if [ -z "${env_file}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if [ ! -f "${env_file}" ]; then
        err "${env_file}: environment file cannot be found."
        exit ${EX_NOINPUT}
    fi

    safe_exc cp -a -- "${env_file}" "${PROJECTSDIR}/${project}/.env"

    return ${EX_OK}
}

littlejet_schedule()
{
    local lockfile
    lockfile="$1"

    shift

    local errlevel

    lockf -st 0 "${lockfile}" "$0" run-script "$@"

    errlevel=$?

    if [ ${errlevel} -eq ${EX_TEMPFAIL} ]; then
        return ${EX_OK}
    else
        return ${errlevel}
    fi
}

littlejet_show()
{
    local project
    project="$1"

    if [ -n "${project}" ]; then
        local errlevel
        
        local project_info
        project_info=`_littlejet_show "${project}" 2>&1`

        errlevel=$?

        printf "%s\n" "${project_info}"

        return ${errlevel}
    else
        local projects
        projects=`littlejet_get-projects` || exit $?

        local output
        output=`tempdir` || exit $?

        atexit_add "removedir \"${output}\""

        debug "Retrieving information ..."

        local nproc=0

        for project in ${projects}; do
            littlejet_show "${project}" > "${output}/${project}.out" 2>&1 &

            atexit_add "safe_kill $! $$"

            nproc=$((nproc+1))

            debug "Job:${nproc}, Total:${NCPU}"

            if [ ${nproc} -ge ${NCPU} ]; then
                debug "Waiting for '${nproc}' jobs"

                nproc=0

                wait || exit $?
            fi
        done

        wait || exit $?

        for project in ${projects}; do
            local outfile
            outfile="${output}/${project}.out"

            if [ -f "${outfile}" ]; then
                cat -- "${outfile}"
            fi
        done

        removedir "${output}"
    fi

    return ${EX_OK}
}

_littlejet_show()
{
    local project
    project="$1"

    _basic_project_checks "${project}"

    local nodes
    nodes=`littlejet_get-nodes "${project}" 2> /dev/null`

    echo "project:"
    echo "  name: ${project}"

    if _is_dirty "${project}"; then
        echo "  dirty: true"
    else
        echo "  dirty: false"
    fi

    if [ -z "${nodes}" ]; then
        return ${EX_OK}
    fi

    echo "  nodes:"

    local node
    for node in ${nodes}; do
        echo "    node:"
        echo "      name: ${node}"

        local labels
        labels=`littlejet_get-labels "${project}" "${node}" 2> /dev/null`

        if [ -n "${labels}" ]; then
            echo "      labels: ${node}"

            local label
            for label in ${labels}; do
                echo "        label:"
                echo "          name: ${label}"
                
                local value=`littlejet_get-label "${project}" "${node}" "${label}"` || exit $?

                echo "          value: ${value}"
            done
        fi

        local errlevel

        local errmsg
        errmsg=`testnode "${node}" 2>&1`

        errlevel=$?

        if [ ${errlevel} -eq 0 ]; then
            echo "      status: OK"
            echo "      code: 0"
        else
            echo "      status: FAIL"
            echo "      code: ${errlevel}"
            echo "      message: ${errmsg}"

            continue
        fi

        echo "      remote:"

        local appjail_version
        appjail_version=`remote_exc "${node}" "NO" "NO" appjail version 2>&1`

        errlevel=$?

        if [ ${errlevel} -eq 0 ]; then
            echo "        appjail:"
            echo "          version: ${appjail_version}"
        else
            echo "        appjail:"
            echo "          version: ERROR"
            echo "          message: ${appjail_version}"
        fi

        local director_version
        director_version=`remote_exc "${node}" "NO" "NO" appjail-director --version 2>&1`

        errlevel=$?

        if [ ${errlevel} -eq 0 ]; then
            echo "        director:"
            echo "          version: ${director_version}"
        else
            echo "        director:"
            echo "          version: ERROR"
            echo "          message: ${director_version}"
        fi

        errmsg=`run_director "${project}" "${node}" "NO" "NO" check 2>&1`

        errlevel=$?

        if [ ${errlevel} -eq 0 ]; then
            local project_info
            project_info=`run_director "${project}" "${node}" "YES" "NO" describe` || exit $?

            local state
            state=`echo -e "${project_info}" | safe_exc jq -r .state` || exit $?

            echo "        status: ${state}"

            local services
            services=`echo -e "${project_info}" | safe_exc jq -r '.services'`

            local services_length
            services_length=`echo -e "${services}" | jq -r length` || exit $?

            if [ ${services_length} -eq 0 ]; then
                continue
            fi

            echo "        services:"

            local service_index=0

            while [ ${service_index} -lt ${services_length} ]; do
                local service
                service=`echo -e "${services}" | safe_exc jq -r ".[${service_index}]"` || exit $?

                local service_name
                service_name=`echo -e "${service}" | safe_exc jq -r '.name'` || exit $?

                local service_status_code
                service_status_code=`echo -e "${service}" | safe_exc jq -r '.status'` || exit $?

                local service_status

                if [ ${service_status_code} -eq 0 ]; then
                    service_status="RUNNING"
                elif [ ${service_status_code} -eq 1 ]; then
                    service_status="STOPPED"
                else
                    service_status="FAILED"
                fi

                local service_jail
                service_jail=`echo -e "${service}" | safe_exc jq -r '.jail'` || exit $?

                echo "          service:"
                echo "            name: ${service_name}"
                echo "            status: ${service_status}"
                echo "            code: ${service_status_code}"
                echo "            jail: ${service_jail}"

                _littlejet_show_healthcheckers "${node}" "${service_jail}"

                _littlejet_show_stats "${node}" "${service_jail}" "${service_status}"

                service_index=$((service_index+1))
            done
        elif [ ${errlevel} -eq ${EX_NOINPUT} ]; then
            echo "        status: PROJECT_NOT_FOUND"
        else
            echo "        status: ERROR"
            echo "        message: ${errmsg}"
        fi
    done
}

_littlejet_show_healthcheckers()
{
    local node
    node="$1"

    local service_jail
    service_jail="$2"

    local service_status
    service_status="$3"

    local errlevel

    local healthcheckers
    healthcheckers=`remote_exc "${node}" "NO" "NO" appjail healthcheck list -eHIpt -- "${service_jail}" nro 2>&1`

    errlevel=$?

    if [ ${errlevel} -ne 0 ]; then
        echo "            healthcheckers:"
        echo "              error: ${errlevel}"
        echo "              message: ${healthcheckers}"
        exit ${errlevel}
    fi

    if [ -n "${healthcheckers}" ]; then
        echo "            healthcheckers:"

        local healthchecker

        for healthchecker in ${healthcheckers}; do
            echo "              ${healthchecker}:"

            local column

            for column in enabled health_cmd health_type interval kill_after name recover_cmd recover_kill_after recover_timeout recover_timeout_signal recover_total recover_type retries start_period status timeout timeout_signal; do
                local value
                value=`remote_exc "${node}" "NO" "NO" appjail healthcheck get -n ${healthchecker} -- "${service_jail}" ${column} 2>&1`

                errlevel=$?

                if [ ${errlevel} -ne 0 ]; then
                    echo "                ${column}:"
                    echo "                  status: ${errlevel}"
                    echo "                  message: ${value}"
                fi

                if [ -z "${value}" ]; then
                    continue
                fi

                echo "                ${column}: ${value}"
            done
        done
    fi
}

_littlejet_show_stats()
{
    local node
    node="$1"

    local service_jail
    service_jail="$2"

    local service_status
    service_status="$3"

    if [ "${service_status}" != "RUNNING" ]; then
        return 0
    fi

    local errlevel

    local racct_enable
    racct_enable=`remote_exc "${node}" "NO" "NO" sysctl -n kern.racct.enable 2>&1`

    errlevel=$?

    if [ -z "${racct_enable}" ]; then
        echo "            stats:"
        echo "              error: ${errlevel}"
        echo "              message: ${racct_enable}"
        exit ${errlevel}
    fi

    if [ "${racct_enable}" != 1 ]; then
        return 0
    fi

    echo "            stats:"

    local stat

    for stat in cputime datasize stacksize coredumpsize memoryuse memorylocked maxproc openfiles vmemoryuse pseudoterminals swapuse nthr msgqqueued msgqsize nmsgq nsem nsemop nshm shmsize wallclock pcpu readbps writebps readiops writeiops; do
        local value
        value=`remote_exc "${node}" "NO" "NO" appjail limits stats -eHIpt -- "${service_jail}" ${stat} 2>&1`

        errlevel=$?

        if [ ${errlevel} -ne 0 ]; then
            echo "                ${stat}:"
            echo "                  status: ${errlevel}"
            echo "                  message: ${value}"
        fi

        if [ -z "${value}" ]; then
            continue
        fi

        echo "                ${stat}: ${value}"
    done
}

littlejet_version()
{
    stdout "%%LITTLEJET_VERSION%%"

    return ${EX_OK}
}

_basic_label_checks()
{
    local project
    project="$1"

    local node
    node="$2"

    local label
    label="$3"

    if [ -z "${label}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if ! checklabelname "${label}"; then
        err "${label}: invalid label name."
        exit ${EX_DATAERR}
    fi

    if ! checklabel "${project}" "${node}" "${label}"; then
        err "${label}: label cannot be found."
        exit ${EX_NOINPUT}
    fi
}

_basic_node_checks()
{
    local project
    project="$1"

    local node
    node="$2"

    if [ -z "${node}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if ! checknodename "${node}"; then
        err "${node}: invalid node name."
        exit ${EX_DATAERR}
    fi

    if ! checknode "${project}" "${node}"; then
        err "${node}: node cannot be found."
        exit ${EX_NOINPUT}
    fi
}

_basic_project_checks()
{
    local project
    project="$1"

    if [ -z "${project}" ]; then
        littlejet_usage
        exit ${EX_USAGE}
    fi

    if ! checkprojectname "${project}"; then
        err "${project}: invalid project name."
        exit ${EX_DATAERR}
    fi

    if ! checkproject "${project}"; then
        err "${project}: project cannot be found."
        exit ${EX_NOINPUT}
    fi
}

_exit_if_dirty()
{
    if _is_dirty "$1"; then
        err "${project}: project is dirty. You need to re-create it."
        exit ${EX_NOPERM}
    fi
}

_is_dirty()
{
    if [ ! -f "${PROJECTSDIR}/$1/.done" ]; then
        return 0
    else
        return 1
    fi
}

littlejet_usage()
{
    local program
    program=`safe_exc basename -- "$0"` || exit $?

    cat << EOF
usage: ${program} add-label <project> <node> <label>=<value> ...
       ${program} add-node [-T] <project> <node>
       ${program} copy [-fN] <project> <new-project>
       ${program} copy-nodes [-O] <src-project> <dst-project> [<node>]
       ${program} create [-f] <project> [<director-file>]
       ${program} del-label <project> <node> <label>
       ${program} del-labels <project> <node>
       ${program} del-node <project> <node>
       ${program} del-nodes <project>
       ${program} destroy <project>
       ${program} get-label <project> <node> <label>
       ${program} get-labels <project> <node>
       ${program} get-nodes <project>
       ${program} get-projects
       ${program} rename <project> <new-project>
       ${program} run-appjail [-CHPs] [-p <project>] [-n <node>] <appjail-command> [<args> ...]
       ${program} run-cmd [-CHPs] [-p <project>] [-n <node>] <command> [<args> ...]
       ${program} run-director [-CHPs] [-p <project>] [-n <node>] <director-command> [<args> ...]
       ${program} run-script [-p <project>] <run-script> [<args> ...]
       ${program} schedule <lock-file> <args> ...
       ${program} set-director <project> <director-file>
       ${program} set-env <project> <env-file>
       ${program} show [<project>]
       ${program} usage
       ${program} version
EOF
}

main "$@"
