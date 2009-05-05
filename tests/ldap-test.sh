#!/bin/bash
# vim:et:ft=sh:sts=2:sw=2:

# LDAP directory test suite
# Author: Farzad FARID <ffarid@pragmatic-source.com>
# Copyright (c) 2009 Mediatech, Pragmatic Source
# License: GPLv3
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This test suite controls the conformity of the OpenLDAP setup with
# the customer's needs.
#
# Check http://code.google.com/p/shunit2/ for more information on
# shUnit2 - xUnit based unit testing for Unix shell scripts


# Consider unset variables as errors
set -u

# Note that we use a pre-generated LDIF file as the LDAP DIT during
# tests, it is called "ldap-test.ldif".
# Any important DIT modification must be reproduced in this file
# during the OpenLDAP integration.
oneTimeSetUp() {
  source ldap-test.conf

  # XXX We need access to the shunit temporary directory with a
  # non-root user. This is kind of hacky.
  chmod 755 ${__shunit_tmpDir}

  # Run our own copy of slapd
  LDAP_CONFDIR="${shunit_tmpDir}/etc-ldap"
  LDAP_RUNDIR="${shunit_tmpDir}/var-run-slapd"
  LDAP_DBDIR="${shunit_tmpDir}/var-lib-ldap"
  mkdir -p $LDAP_CONFDIR $LDAP_RUNDIR $LDAP_DBDIR
  cp -a /etc/ldap/* $LDAP_CONFDIR
  sed -i -e "s#/etc/ldap#${LDAP_CONFDIR}#g" \
    -e "s#/var/run/slapd#${LDAP_RUNDIR}#g" \
    -e "s#/var/lib/ldap#${LDAP_DBDIR}#g" ${LDAP_CONFDIR}/slapd.conf
  chown openldap:openldap $LDAP_RUNDIR $LDAP_DBDIR
  chmod 755 $LDAP_RUNDIR $LDAP_DBDIR
  # The test LDAP server will be started by the first test
}

oneTimeTearDown() {
  # Stop our slapd test server
  kill $(cat ${LDAP_RUNDIR}/slapd.pid)
  # The LDAP directories we set up previously are automatically destroyed by shunit2
}

# We really load and start the slapd server in the first test
testLoadAndStartSlapd() {
  local RC

  sudo -u openldap ${SLAPADD} -f ${LDAP_CONFDIR}/slapd.conf -l ldap-test.ldif 
  RC=$?
  assertTrue "Loading of test LDIF file failed" $RC || startSkipping
  ${SLAPD} -n "ldap-test" -h "${LDAPN_URI} ${LDAPS_URI} ldapi:///" -g openldap -u openldap -f ${LDAP_CONFDIR}/slapd.conf
  RC=$?
  assertTrue "Failed to start slapd server" $RC || startSkipping
  sleep 2
  assertTrue "Failed to start slapd server" "[ -f ${LDAP_RUNDIR}/slapd.pid ]"
}

testSSLConnection() {
  local OUTPUT RC

  OUTPUT=`echo "" | openssl s_client -CApath /etc/ssl/certs -connect ${LDAPS_HOST}:${LDAPS_PORT} 2>/dev/null`
  echo $OUTPUT | grep -q "Verify return code: 0 (ok)"
  RC=$?
  assertTrue "Cannot connect to LDAP/SSL or certificate chain invalid" $RC
}

# Now launch the test suite
. shunit2
