# Contrôle des tests et installation de fichiers pour le
# projet OpenLDAP


TEST_DIR	:= $(shell pwd)/tests
SERVER_NAME	:= $(shell hostname --fqdn)

###############################################################"
## Détermine le nom du serveur LDAP qui complète celui-ci.
## Par convention, si le nom du premier se
## termine par "1", le nom de l'autre doit se terminer par "2".
#TEST_HOSTNAME1 := $(SERVER_NAME:%1=)
#TEST_HOSTNAME2 := $(SERVER_NAME:%2=)
#ifeq "$(TEST_HOSTNAME1)" ''
#    # On est sur la machine dont le nom se finit par "1"
#    SERVER_NAME_OTHER := $(SERVER_NAME:%1=%2)
#    SERVER_NUMBER := 1
#else ifeq "$(TEST_HOSTNAME2)" ''
#    # On est sur la machine dont le nom se finit par "2"
#    SERVER_NAME_OTHER := $(SERVER_NAME:%2=%1)
#    SERVER_NUMBER := 2
#else
#    # Le nom de cette machine ne se finit par par "1" ou "2" !
#    $(error Ce Makefile ne peut fonctionner que si le nom du serveur LDAP se finit par '1' ou '2')
#endif
###############################################################"
# local.streamlike & www.abruti.org
ifeq "$(SERVER_NAME)" 'local.streamlike.com'
    # On est sur la machine 1
    SERVER_NAME_OTHER := www.abruti.org
    SERVER_NUMBER := 1
else ifeq "$(SERVER_NAME)" 'www.abruti.org'
    # On est sur la machine 2
    SERVER_NAME_OTHER := local.streamlike.com
    SERVER_NUMBER := 2
else
    $(error Je ne trouve pas les noms de machines.)
endif


export TEST_DIR SERVER_NAME SERVER_NAME_OTHER SERVER_NUMBER

.PHONY: diag tests install

all:
	@echo "Commandes disponibles :"
	@echo " make tests : lance les tests"
	@echo " make install_schema : installe le schéma LDAP Mediatech en production"
	@echo " make install_config : installe les fichier de configuration slapd.conf, ldap.conf et le cron de backup en production"
	@echo " make install_monit : installe le fichier de configuration Monit et redémarre celui-ci"
	@echo " make export_ldap : Recrée la base LDIF de test à partir de la base de production"
	@echo " make diag : affiche quelques infos sur le Makefile"


diag:
	@echo test_dir : $(TEST_DIR)

tests: create_config
	@echo Running tests...
	cd $(TEST_DIR) && ./ldap-test.sh

install_schema:
	@echo "Installation du schéma LDAP Mediatech et redémarrage d'OpenLDAP"
	cp schema/mediatech.schema /etc/ldap/schema
	/etc/init.d/slapd restart

# Crée le fichier slapd.conf spécifique à cette machine
create_config:
	@echo "Création de slapd.conf pour ${SERVER_NAME}..."
	@echo "#######################################################################"  > config/slapd.conf
	@echo "# WARNING: THIS FILE WAS AUTOMATICALLY GENERATED FROM A TEMPLATE FILE"    >> config/slapd.conf
	@echo "# CALLED slapd.conf.template. DO NOT MODIFY IT DIRECTLY IF YOU ARE USING" >> config/slapd.conf
	@echo "# THE TEMPLATE FILE FOR DEVELOPMENT AND CONFIGURATION."                   >> config/slapd.conf
	@echo "#######################################################################"  >> config/slapd.conf
	@echo ""                                                                         >> config/slapd.conf
	sed -e "s/@@SERVER_NAME@@/${SERVER_NAME}/g" \
	    -e "s/@@SERVER_NAME_OTHER@@/${SERVER_NAME_OTHER}/g" \
	    -e "s/@@SERVER_NUMBER@@/${SERVER_NUMBER}/g" config/slapd.conf.template >> config/slapd.conf

install_config: create_config
	@echo "Installation de la configuration LDAP Mediatech, du cron de backup et redémarrage d'OpenLDAP"
	cp config/slapd.conf /etc/ldap
	rm -f config/slapd.conf
	cp config/ldap.conf /etc/ldap
	cp config/openldap-backup.cron /etc/cron.d/openldap-backup
	/etc/init.d/slapd restart

install_monit:
	@echo "Mise à jour de la configuration Monit"
	cp config/monit /etc/default/monit
	cp config/monitrc /etc/monit/monitrc
	/etc/init.d/monit restart

export_ldap:
	@echo "Exportation de la base LDAP de production en fichier LDIF de test"
	slapcat | grep -Ev "(structuralObjectClass|entryUUID|creatorsName|createTimestamp|entryCSN|modifiersName|modifyTimestamp|contextCSN)" > $(TEST_DIR)/ldap-test.ldif

# On vérifie qu'on est sur la machine dont le nom se termine par "1",
# si oui, copie sur l'autre machine dont le nom se termine par "2".
sync_src:
	@echo "Copie du répertoire de développement sur le serveur LDAP numéro 2..."
	@if [ "${SERVER_NUMBER}" = "1" ]; then \
	    rsync -a --exclude "*.swp" --delete /usr/src/ldap/ ${SERVER_NAME_OTHER}:/usr/src/ldap; \
	    echo "OK" ; \
	else \
	    echo "ERREUR : Cette commande doit être lancée sur le serveur LDAP numéro 1 uniquement"; \
	    exit 1; \
	fi

