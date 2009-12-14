OPENSSL=openssl

ifndef DIR
DIR := .
endif

ifdef PASSWORD
P12PASS := true
else
P12PASS := @echo No PASSWORD defined. && false
endif

.PRECIOUS: %/testca
.PHONY: %/clean target all p12pass

all: client server

client: p12pass
	$(MAKE) target DIR=$(DIR) TARGET=client EXTENSIONS=client_ca_extensions

server: p12pass
	$(MAKE) target DIR=$(DIR) TARGET=server EXTENSIONS=server_ca_extensions

p12pass:
	$(P12PASS)

target: testca
	mkdir $(DIR)/$(TARGET)
	{ ( cd $(DIR)/$(TARGET) && \
	    openssl req -newkey rsa:2048 -keyout key.pem -keyform PEM -out \
	      req.pem -subj /CN=$$(hostname)/O=$(TARGET)/L=$$$$/ -outform PEM \
	      -nodes && \
	    cd ../testca && \
	    openssl ca -config openssl.cnf -in ../$(TARGET)/req.pem -out \
	      ../$(TARGET)/cert.pem -notext -batch -extensions \
	      $(EXTENSIONS) && \
	    cd ../$(TARGET) && \
	    openssl pkcs12 -export -out keycert.p12 -in cert.pem -inkey key.pem \
	      -passout pass:$(PASSWORD) ) || (rm -rf $(DIR)/$(TARGET) && false); }

testca:
	mkdir $(DIR)/testca
	cp openssl.cnf $(DIR)/testca/openssl.cnf
	{ ( cd $(DIR)/testca && \
	    mkdir certs private && \
	    chmod 700 private && \
	    echo 01 > serial && \
	    touch index.txt && \
	    openssl req -x509 -config openssl.cnf -newkey rsa:2048 -days 365 \
	      -out cacert.pem -outform PEM -subj /CN=MyTestCA/L=$$$$/ -nodes && \
	    openssl x509 -in cacert.pem -out cacert.cer -outform DER ) \
	  || (rm -rf $@ && false); }

clean:
	rm -rf $(DIR)/testca
	rm -rf $(DIR)/server
	rm -rf $(DIR)/client
