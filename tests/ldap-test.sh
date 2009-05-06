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

TEST_DIR=$(dirname $0)
export TEST_DIR

# Note that we use a pre-generated LDIF file as the LDAP DIT during
# tests, it is called "ldap-test.ldif".
# Any important DIT modification must be reproduced in this file
# during the OpenLDAP integration.
oneTimeSetUp() {
  source ${TEST_DIR}/ldap-test.conf

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

  # Some temporary filenames
  TMPFILE1=${shunit_tmpDir}/tmpfile1
  TMPFILE2=${shunit_tmpDir}/tmpfile2
}

oneTimeTearDown() {
  # Stop our slapd test server
  kill $(cat ${LDAP_RUNDIR}/slapd.pid)
  # The LDAP directories we set up previously are automatically destroyed by shunit2
}

# Clean temp files between tests
tearDown() {
  rm -f ${TMPFILE1} ${TMPFILE2}
}

# --------------------------------
# Helper functions
# --------------------------------


ldapsearch_anon() { ${LDAPSEARCH} -x -H "${LDAP_URI}" -b "${LDAP_BASE}" $@ ; }
ldapsearch_admin() { ${LDAPSEARCH} -x -H "${LDAP_URI}" -b "${LDAP_BASE}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" $@ ; }
ldapmodify_admin() { ${LDAPMODIFY} -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" $@ ; }


# ---------------------------------
# Tests
# ---------------------------------


# We really load and start the slapd server in the first test
testLoadAndStartSlapd() {
  local RC

  sudo -u openldap ${SLAPADD} -f ${LDAP_CONFDIR}/slapd.conf -l ldap-test.ldif 
  RC=$?
  assertTrue "Loading of test LDIF file failed" $RC || startSkipping
  ${SLAPD} -n "ldap-test" -h "${LDAPN_URI} ${LDAPS_URI} ldapi:///" -g openldap -u openldap -f ${LDAP_CONFDIR}/slapd.conf
  RC=$?
  assertTrue "Failed to start slapd server" $RC || startSkipping
  sleep 1
  assertTrue "Failed to start slapd server" "[ -f ${LDAP_RUNDIR}/slapd.pid ]"
}

testSSLConnection() {
  local OUTPUT RC

  echo "" | openssl s_client -CApath /etc/ssl/certs -connect ${LDAPS_HOST}:${LDAPS_PORT} > ${TMPFILE1} 2>/dev/null
  grep -q "Verify return code: 0 (ok)" ${TMPFILE1}
  RC=$?
  assertTrue "Cannot connect to LDAP/SSL or certificate chain invalid" $RC
}

testFindCompany() {
  local OUTPUT RC
  
  ldapsearch_admin -LLL '(&(objectClass=mtOrganization)(o=TBWA))' > ${TMPFILE1}

  grep -qE '^dn: o=TBWA,ou=Customers,dc=mediatech,dc=fr$' ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find TBWA customer" $RC

  grep -qE '^mtStatus: online$' ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find customer attribute 'mtStatus'" $RC
}

testFindMediatech() {
  local OUTPUT GREPOUT RC

  ldapsearch_admin -b "ou=Internal,$LDAP_BASE" -LLL '(objectClass=mtOrganization)' > ${TMPFILE1}

  GREPOUT=$(grep -E '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "There should be only one company under ou=Internal" 1 "${GREPOUT}" || return

  GREPOUT=$(grep -E '^o:' ${TMPFILE1})
  assertEquals "Cannot find Mediatech object" "o: Mediatech" "${GREPOUT}" 
}

testModifyCompany() {
  local OUTPUT GREPOUT RC

  ldapsearch_admin -LLL '(&(objectClass=mtOrganization)(o=TBWA)(mtStatus=online))' > ${TMPFILE1}

  GREPOUT=$(grep -E '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Cannot find TBWA customer with online status" 1 "${GREPOUT}" || return

  cat <<EOT > ${TMPFILE1}
dn: o=TBWA,ou=Customers,dc=mediatech,dc=fr
changetype: modify
replace: mtStatus
mtStatus: offline
EOT
  ldapmodify_admin -f ${TMPFILE1}
  RC=$?
  assertTrue "LDAP modification failed" $RC || return

  ldapsearch_admin -LLL '(&(objectClass=mtOrganization)(o=TBWA)(mtStatus=offline))' > ${TMPFILE1}

  GREPOUT=$(grep -E '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Cannot find TBWA customer with offline status" 1 "${GREPOUT}"
}

testFindMultipleCompanies() {
  local OUTPUT GREPOUT RC

  ldapsearch_admin -LLL '(&(objectClass=mtOrganization)(o=Autoworld))' > ${TMPFILE1}
}


# Now launch the test suite
. ${TEST_DIR}/shunit2
