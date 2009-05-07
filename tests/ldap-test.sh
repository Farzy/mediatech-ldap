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
  # Copy the local schemas file over the production files, just in case
  # the development version is newer
  cp ${TEST_DIR}/../schema/*.schema ${LDAP_CONFDIR}/schema
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


ldapsearch_anon() { ${LDAPSEARCH} -x -H "${LDAP_URI}" -b "${LDAP_BASE}" "$@" ; }
ldapsearch_admin() { ${LDAPSEARCH} -x -H "${LDAP_URI}" -b "${LDAP_BASE}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" "$@" ; }
ldapmodify_admin() { ${LDAPMODIFY} -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" "$@" ; }

# Extract a given attribute's value from stdin (must be in LDIF format)
# Argument #1 : attribute name
get_attr_value() {
  local ATTR_NAME

  ATTR_NAME=$1
  [ -z "${ATTR_NAME}" ] && { fail "Missing attribute name in call to 'getAttributeValue' in unit test" ; return; }

  # - The perl command joins splitted long lines back together. See
  #   http://www.openldap.org/lists/openldap-software/200504/msg00212.html
  # The 'sed' line extracts lines starting with 'attribute_name:'
  cat - | perl -p -00 -e 's/\r\n //g; s/\n //g' | sed -n -e "s/^${ATTR_NAME}://p" | while read raw_value; do
    # See if the line starts with ": ", in which case the attribute's value is base64 encoded,
    # otherwise it is in plain text and will begin with ' '.
    value="${raw_value#: }"
    if [ "${value}" = "${raw_value}" ]; then
      # No encoding, but don't forget to get rid of the first space at the beginning of the line
      echo ${value# }
    else
      # Base64 encoding, must also add a newline, because openssl does not add one.
      echo ${value} | openssl base64 -d ; echo
    fi
  done
}


# ---------------------------------
# Tests
# ---------------------------------


# We really load and start the slapd server in the first test
test_Load_and_Start_slapd() {
  local RC

  sudo -u openldap ${SLAPADD} -f ${LDAP_CONFDIR}/slapd.conf -l ldap-test.ldif 
  RC=$?
  assertTrue "Loading of test LDIF file failed" "$RC" || startSkipping
  ${SLAPD} -n "ldap-test" -h "${LDAPN_URI} ${LDAPS_URI} ldapi:///" -g openldap -u openldap -f ${LDAP_CONFDIR}/slapd.conf
  RC=$?
  assertTrue "Failed to start slapd server" "$RC" || startSkipping
  sleep 1
  assertTrue "Failed to start slapd server" "[ -f ${LDAP_RUNDIR}/slapd.pid ]"
}

test_SSL_Connection() {
  local OUTPUT RC

  echo "" | openssl s_client -CApath /etc/ssl/certs -connect ${LDAPS_HOST}:${LDAPS_PORT} > ${TMPFILE1} 2>/dev/null
  grep -q "Verify return code: 0 (ok)" ${TMPFILE1}
  RC=$?
  assertTrue "Cannot connect to LDAP/SSL or certificate chain invalid" "$RC"
}

test_Find_All_Customer_Options() {
  local OUTPUT

  # XXX : ldapsearch returns strings containing accents as base64, and cannot decode it automatically...
  ldapsearch_admin -LLL -b "ou=Internal,${LDAP_BASE}" '(&(objectClass=mtCustomerOptionList)(cn=All Customer Options))' mtOption | \
    get_attr_value 'mtOption' | sort > ${TMPFILE1}
  # Count lines
  OUTPUT=$(cat ${TMPFILE1} | wc -l)
  assertEquals "Wrong number of customer options found" 8 "${OUTPUT}" || return
  # Compare to expected list
  cmp ${TMPFILE1} <<EOT >/dev/null 2>&1
Classement
Encodage HQ
Filtrage Geoloc
Geo Blocking
Gestion du nombre de connexions
Reporting Géolocalisation
Webinar
WebTV
EOT
  RC=$?
  assertTrue "Global option list is incorrect" "$RC"
}

test_Find_All_and_Online_Customers() {
  local OUTPUT

  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(objectClass=mtOrganization)' o > ${TMPFILE1}
  OUTPUT=$(grep '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Wrong number of total customers found" 5 "${OUTPUT}" || return

  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(mtStatus=online))' o > ${TMPFILE1}
  OUTPUT=$(grep '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Wrong number of online customers found" 4 "${OUTPUT}"
}

test_Find_Customer() {
  local OUTPUT RC
  
  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=TBWA))' > ${TMPFILE1}

  grep -qE '^dn: o=TBWA,ou=Customers,dc=mediatech,dc=fr$' ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find TBWA customer" "$RC" || return

  grep -qE '^mtStatus: online$' ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find customer attribute 'mtStatus'" "$RC"
}

test_Find_Company_Options() {
  local RC COMPANY_DN OPTIONS

  # Find the customer "TBWA"
  COMPANY_DN=$(ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=TBWA))' | get_attr_value 'dn')
  # Find the customer's options
  ldapsearch_admin -LLL -b "cn=options,${COMPANY_DN}" -s base '(objectClass=mtCustomerOptionList)' mtOption | \
    get_attr_value 'mtOption' | sort > ${TMPFILE1}
  # Compare to expected list
  cmp ${TMPFILE1} <<EOT >/dev/null 2>&1
Classement
Webinar
WebTV
EOT
  RC=$?
  assertTrue "Customer's option list is incorrect" "$RC"
}

test_Find_Mediatech() {
  local OUTPUT RC

  ldapsearch_admin -b "ou=Internal,$LDAP_BASE" -LLL '(objectClass=mtOrganization)' > ${TMPFILE1}

  GREPOUT=$(grep -E '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "There should be only one company under ou=Internal" 1 "${GREPOUT}" || return

  GREPOUT=$(grep -E '^o:' ${TMPFILE1})
  assertEquals "Cannot find Mediatech object" "o: Mediatech" "${GREPOUT}" 
}

test_Modify_Company() {
  local OUTPUT RC

  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=TBWA)(mtStatus=online))' > ${TMPFILE1}

  GREPOUT=$(grep -E '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Cannot find TBWA customer with online status" 1 "${GREPOUT}" || return

  cat <<EOT > ${TMPFILE1}
dn: o=TBWA,ou=Customers,dc=mediatech,dc=fr
changetype: modify
replace: mtStatus
mtStatus: offline
EOT
  ldapmodify_admin -f ${TMPFILE1} >/dev/null
  RC=$?
  assertTrue "LDAP modification failed" "$RC" || return

  ldapsearch_admin -LLL '(&(objectClass=mtOrganization)(o=TBWA)(mtStatus=offline))' > ${TMPFILE1}

  GREPOUT=$(grep -E '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Cannot find TBWA customer with offline status" 1 "${GREPOUT}"
}

test_Find_Multiple_Companies() {
  local OUTPUT RC ROOT_COMPANY_DN

  # Find the root company "Autoworld"
  ROOT_COMPANY_DN=$(ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=Autoworld))' | get_attr_value 'dn')
  RC=$?
  assertTrue "Cannot find root company's DN" "$RC" || return
  assertEquals "o=Autoworld returned a wrong company" "o=Autoworld,ou=Customers,dc=mediatech,dc=fr" "${ROOT_COMPANY_DN}" || return

  # Now find the root company's sub-companies
  ldapsearch_admin -LLL -b "${ROOT_COMPANY_DN}" -s one '(objectClass=mtOrganization)' o | get_attr_value 'o' | sort > ${TMPFILE1}
  assertEquals "Wrong number of subcompanies" 2 $(cat ${TMPFILE1} | wc -l) || return
  assertEquals "Subcompany one is not the expected name" "Autoworld France" "$(head -n 1 ${TMPFILE1})" || return
  assertEquals "Subcompany two is not the expected name" "Autoworld Italy" "$(tail -n 1 ${TMPFILE1})" || return
}

test_Find_Regular_User_by_Uid() {
  local OUTPUT RC

  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(uid=wsmith))' uid > ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find Regular user" "$RC" || return
  OUTPUT=$(cat ${TMPFILE1} | get_attr_value 'dn')
  assertEquals "Cannot find regular user" \
    "cn=Will Smith,o=Autoworld France,o=Autoworld,ou=Customers,${LDAP_BASE}" "${OUTPUT}"
}

test_Find_Regular_User_by_Uid_or_Alias() {
  local OUTPUT RC

  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=johnny)(mtAlias=johnny)))' uid > ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find Regular user by alias" "$RC" || return
  OUTPUT=$(cat ${TMPFILE1} | get_attr_value 'dn')
  assertEquals "Search for user by alias returned wrong entry" \
    "cn=John Doe,o=Autoworld France,o=Autoworld,ou=Customers,${LDAP_BASE}" "${OUTPUT}"
}

test_Find_Mediatech_User() {
  local OUTPUT RC

  ldapsearch_admin -LLL -b "ou=Internal,$LDAP_BASE" '(&(objectClass=mtPerson)(uid=asimonneau))' > ${TMPFILE1}
  RC=$?
  assertTrue "Cannot find Mediatech user" "$RC" || return
  OUTPUT=$(cat ${TMPFILE1} | get_attr_value 'dn')
  assertEquals "Cannot find Mediatech user" "cn=Antony Simonneau,o=Mediatech,ou=Internal,${LDAP_BASE}" "${OUTPUT}"
}

test_Normal_User_Can_Only_Bind() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Customers" ou
  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=wsmith)(mtAlias=wsmith)))' > ${TMPFILE1}
  USERDN=$(cat ${TMPFILE1} | get_attr_value 'dn')

  # Should accept good password
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w pipo)
  RC=$?
  assertTrue "User cannot authenticate correctly" "$RC" || return
  assertEquals "ldapwhoami returned wrong user DN" "dn:${USERDN}" "${OUTPUT}" || return

  # Should reject wrong password
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w XXXX 2>/dev/null)
  RC=$?
  assertFalse "User should not be able to authenticate with wrong password" "$RC"
}

test_Change_User_Password_as_Admin() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Customers" ou
  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=wsmith)(mtAlias=wsmith)))' > ${TMPFILE1}
  USERDN=$(cat ${TMPFILE1} | get_attr_value 'dn')

  # Change the password
  ${LDAPPASSWD} -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" -a pipo -s goodsecret "$USERDN"
  RC=$?
  assertTrue "Failed to change user password" "$RC" || return
  
  # Should accept new password
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w goodsecret)
  RC=$?
  assertTrue "User cannot authenticate correctly" "$RC"
}

test_Mediatech_User_Can_Only_Bind() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Internal" ou
  ldapsearch_admin -LLL -b "ou=Internal,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=antony)(mtAlias=antony)))' > ${TMPFILE1}
  USERDN=$(cat ${TMPFILE1} | get_attr_value 'dn')
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w pipo)
  RC=$?
  assertTrue "Mediatech user cannot authenticate correctly" "$RC" || return
  assertEquals "ldapwhoami returned wrong user DN" "dn:${USERDN}" "${OUTPUT}"
}

test_Normal_User_Cannot_Spoof_Mediatech_Authentication() {
  local OUTPUT RC USERDN

  # Try to find a Mediatech user by "uid" (or "mtAlias") in the "Customers" ou,
  # it should fail.
  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=asimonneau)(mtAlias=asimonneau)))' > ${TMPFILE1}
  USERDN=$(cat ${TMPFILE1} | get_attr_value 'dn')
  assertNull "A customer should not be able to authenticate as a mediatech user" "${USERDN}"
}

test_No_Anonymous_Access() {
  ldapsearch_anon -LLL >/dev/null 2>&1
  RC=$?
  assertFalse "Anonymous LDAP access should be denied" "$RC"
}

test_Find_All_Admins() {
  local OUTPUT RC ORGDN

  # First find meta-company by name
  ldapsearch_admin -LLL -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=Autoworld))' > ${TMPFILE1}
  ORGDN=$(cat ${TMPFILE1} | get_attr_value 'dn')
  # Then find all admin in company and sub-companies
  # Only extract sorted "uid: ...." lines
  ldapsearch_admin -LLL -b "${ORGDN}" '(&(objectClass=mtperson)(employeeType=admin))' uid | get_attr_value 'uid' | sort > ${TMPFILE2}
  cmp ${TMPFILE2} <<-EOT >/dev/null 2>&1
autoworldadmin
jdoe
EOT
  RC=$?
  assertTrue "Cannot find both Autoworld admins" "$RC"
}

test_Find_All_and_Used_Servers() {
  local OUTPUT

  # All Servers
  ldapsearch_admin -LLL -b "ou=Servers,${LDAP_BASE}" '(objectClass=mtServer)' > ${TMPFILE1}
  # Count servers
  OUTPUT=$(grep '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Wrong number of servers found" 3 "${OUTPUT}" || return

  # Used servers
  ldapsearch_admin -LLL -b "ou=Servers,${LDAP_BASE}" '(&(objectClass=mtServer)(owner=*))' > ${TMPFILE1}
  # Count servers
  OUTPUT=$(grep '^dn:' ${TMPFILE1} | wc -l)
  assertEquals "Wrong number of servers found" 2 "${OUTPUT}"
}

test_Find_Customer_Server() {
  local OUTPUT COMPANY_DN

  # Find the customer "TBWA"
  COMPANY_DN=$(ldapsearch_admin -LLL '(&(objectClass=mtOrganization)(o=TBWA))' | sed -n -e 's/^dn: //p')
  # Find TBWA's server
  ldapsearch_admin -LLL -b "ou=Servers,${LDAP_BASE}" "(&(objectClass=mtServer)(owner=${COMPANY_DN}))" mtServerName > ${TMPFILE1}
  OUTPUT=$(cat ${TMPFILE1} | sed -n -e 's/^mtServerName: //p')
  assertEquals "Cannot find customer's server" "dedibox1" "${OUTPUT}"
}

test_Find_Unused_Servers() {
 ldapsearch_admin -LLL -b "ou=Servers,${LDAP_BASE}" "(&(objectClass=mtServer)(!(owner=*)))" mtServerName > ${TMPFILE1}
  OUTPUT=$(cat ${TMPFILE1} | sed -n -e 's/^mtServerName: //p')
  assertEquals "Cannot find unused server" "dedibox3" "${OUTPUT}"
}


# Now launch the test suite
. ${TEST_DIR}/shunit2
