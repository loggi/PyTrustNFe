# -*- coding: utf-8 -*-
# © 2016 Danimar Ribeiro, Trustcode
# License AGPL-3.0 or later (http://www.gnu.org/licenses/agpl.html).

import os
import suds
from base64 import b64encode
from pytrustnfe.xml import render_xml, sanitize_response
from pytrustnfe.client import get_authenticated_client
from pytrustnfe.certificado import (
    extract_cert_and_key_from_pfx,
    load_privatekey_from_pfx,
    rsa_or_ec_sha1_sign,
    save_cert_key,
)
from pytrustnfe.nfse.assinatura import Assinatura


def sign_tag(certificado, **kwargs):
    key = load_privatekey_from_pfx(certificado.pfx, certificado.password)
    if "nfse" in kwargs:
        for item in kwargs["nfse"]["lista_rps"]:
            signed = rsa_or_ec_sha1_sign(key, item["assinatura"])
            item["assinatura"] = b64encode(signed).decode()
    if "cancelamento" in kwargs:
        signed = rsa_or_ec_sha1_sign(key, kwargs["cancelamento"]["assinatura"])
        kwargs["cancelamento"]["assinatura"] = b64encode(signed).decode()


def _send(certificado, method, **kwargs):
    # A little hack to test
    path = os.path.join(os.path.dirname(__file__), "templates")
    if (
        method == "TesteEnvioLoteRPS"
        or method == "EnvioLoteRPS"
        or method == "CancelamentoNFe"
    ):
        sign_tag(certificado, **kwargs)

    if method == "TesteEnvioLoteRPS":
        xml_send = render_xml(path, "EnvioLoteRPS.xml", False, **kwargs)
    else:
        xml_send = render_xml(path, "%s.xml" % method, False, **kwargs)

    use_legacy_endpoint = kwargs.get('nfse', {}).get('use_legacy_endpoint')

    if use_legacy_endpoint:
        base_url = "https://nfe.prefeitura.sp.gov.br/ws/lotenfe.asmx?wsdl"
    else:
        base_url = "https://nfews.prefeitura.sp.gov.br/lotenfe.asmx?WSDL"

    cert, key = extract_cert_and_key_from_pfx(certificado.pfx, certificado.password)
    cert, key = save_cert_key(cert, key)
    client = get_authenticated_client(base_url, cert, key)

    signer = Assinatura(cert, key, certificado.password)
    xml_send = signer.assina_xml(xml_send, "")

    try:
        schema_version = _get_schema_version(method, kwargs)
        response = getattr(client.service, method)(schema_version, xml_send)
    except suds.WebFault as e:
        return {
            "url": base_url,
            "sent_xml": xml_send,
            "received_xml": e.fault.faultstring,
            "object": None,
        }

    response, obj = sanitize_response(response)
    return {"sent_xml": xml_send, "received_xml": response, "object": obj, "url": base_url}


def _get_schema_version(method, kwargs):
    method_to_node_mapper = {
        "ConsultaNFe": "consulta",
        "CancelamentoNFe": "cancelamento",
        "EnvioLoteRPS": "nfse",
        "TesteEnvioLoteRPS": "nfse",
    }

    node_name = method_to_node_mapper.get(method, '')
    node = kwargs.get(node_name, {})
    schema_version = node.get('versao', '1')

    return schema_version

def envio_rps(certificado, **kwargs):
    return _send(certificado, "EnvioRPS", **kwargs)


# Testado pois usa o mesmo xml que o teste_envio_lote_rps
def envio_lote_rps(certificado, **kwargs):
    return _send(certificado, "EnvioLoteRPS", **kwargs)


# Testado
def teste_envio_lote_rps(certificado, **kwargs):
    return _send(certificado, "TesteEnvioLoteRPS", **kwargs)


def cancelamento_nfe(certificado, **kwargs):
    return _send(certificado, "CancelamentoNFe", **kwargs)


# Testado
def consulta_nfe(certificado, **kwargs):
    return _send(certificado, "ConsultaNFe", **kwargs)


# Testado
def consulta_nfe_recebidas(certificado, **kwargs):
    return _send(certificado, "ConsultaNFeRecebidas", **kwargs)


# Testado
def consulta_nfe_emitidas(certificado, **kwargs):
    return _send(certificado, "ConsultaNFeEmitidas", **kwargs)


# Testado
def consulta_lote(certificado, **kwargs):
    return _send(certificado, "ConsultaLote", **kwargs)


# Testado
def consulta_informacoes_lote(certificado, **kwargs):
    return _send(certificado, "ConsultaInformacoesLote", **kwargs)


# Testado
def consulta_cnpj(certificado, **kwargs):
    return _send(certificado, "ConsultaCNPJ", **kwargs)
