# Contrôle des tests et installation de fichiers pour le
# projet OpenLDAP


TEST_DIR	:= $(shell pwd)/tests
export TEST_DIR

.PHONY: diag tests install

all:
	@echo "Commandes disponibles :"
	@echo " make tests : lance les tests"
	@echo " make install_schema : installe le schéma LDAP Mediatech en production"
	@echo " make export_ldap : Recrée la base LDIF de test à partir de la base de production"
	@echo " make diag : affiche quelques infos sur le Makefile"


diag:
	@echo test_dir : $(TEST_DIR)

tests:
	@echo Running tests...
	cd $(TEST_DIR) && ./ldap-test.sh

install_schema:
	@echo "Installation du schéma LDAP Mediatech et redémarrage d'OpenLDAP"
	cp schema/mediatech.schema /etc/ldap/schema
	/etc/init.d/slapd restart

export_ldap:
	@echo "Exportation de la base LDAP de production en fichier LDIF de test"
	slapcat | grep -Ev "(structuralObjectClass|entryUUID|creatorsName|createTimestamp|entryCSN|modifiersName|modifyTimestamp)" > $(TEST_DIR)/ldap-test.ldif
