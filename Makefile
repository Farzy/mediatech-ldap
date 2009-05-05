# Contrôle des tests et installation de fichiers pour le
# projet OpenLDAP


TEST_DIR	:= $(shell pwd)/tests
export TEST_DIR

.PHONY: diag tests install

all:
	@echo "Commandes disponibles :"
	@echo " make tests : lance les tests"
	@echo " make install : installe le schéma LDAP Mediatech en production"
	@echo " make diag : affiche quelques infos sur le Makefile"


diag:
	@echo test_dir : $(TEST_DIR)

tests:
	@echo Running tests...
	cd $(TEST_DIR) && ./ldap-test.sh

install:
	@echo "Installation du schéma LDAP Mediatech et redémarrage d'OpenLDAP"
	cp schema/mediatech.schema /etc/ldap/schema
	/etc/init.d/slapd restart
