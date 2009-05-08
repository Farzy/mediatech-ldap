# Contrôle des tests et installation de fichiers pour le
# projet OpenLDAP


TEST_DIR	:= $(shell pwd)/tests
export TEST_DIR

.PHONY: diag tests install

all:
	@echo "Commandes disponibles :"
	@echo " make tests : lance les tests"
	@echo " make install_schema : installe le schéma LDAP Mediatech en production"
	@echo " make install_config : installe les fichier de configuration slapd.conf, ldap.conf et le cron de backup en production"
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

install_config:
	@echo "Installation de la configuration LDAP Mediatech, du cron de backup et redémarrage d'OpenLDAP"
	cp config/slapd.conf /etc/ldap
	cp config/ldap.conf /etc/ldap
	cp misc/openldap-backup.cron /etc/cron.d/openldap-backup
	/etc/init.d/slapd restart

export_ldap:
	@echo "Exportation de la base LDAP de production en fichier LDIF de test"
	slapcat | grep -Ev "(structuralObjectClass|entryUUID|creatorsName|createTimestamp|entryCSN|modifiersName|modifyTimestamp|contextCSN)" > $(TEST_DIR)/ldap-test.ldif

sync_src:
	@echo "Copie du répertoire de développement sur ldap2"
	if [ "$$(hostname)" = "ldap1" ]; then \
	    rsync -av --exclude "*.swp" --delete /usr/src/ldap/ ldap2:/usr/src/ldap; \
	else \
	    echo "ERREUR : Cette commande doit être lancée sur ldap1 uniquement"; \
	fi

