#!/usr/bin/env python3
"""
Testa IDs de apps Samsung conhecidos, um por um.
Você olha a TV e diz se o app abriu ou não.

Uso:
    python3 tools/testar_apps.py
"""

import asyncio
import json
import ssl
import websockets

TV_IP = '192.168.1.4'
TV_NAME_BASE64 = 'bXlyZW1vdGU='

CANDIDATOS = [
    ('HBO Max',        '3201601007230'),
    ('HBO Max (alt 1)','3201706017365'),
    ('HBO Max (alt 2)','3201907018807'),
    ('Max',            '3202301029760'),
    ('Netflix',        '11101200001'),
    ('Netflix (alt)',  '3201606009684'),
    ('YouTube',        '111299001912'),
    ('YouTube (alt)',  '320151200001'),
    ('Prime Video',    '3201910019365'),
    ('Disney+',        '3201901017640'),
    ('Disney+ (alt)',  '3201901017640'),
    ('Spotify',        '3201606009684'),
    ('Apple TV+',      '3201807016597'),
    ('Globoplay',      '3201703012251'),
]


async def testar_todos():
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    url = (
        f'wss://{TV_IP}:8002/api/v2/channels/samsung.remote.control'
        f'?name={TV_NAME_BASE64}'
    )

    print(f'Conectando em {TV_IP}...')

    async with websockets.connect(url, ssl=ssl_ctx) as ws:
        await ws.recv()
        print('Conectado.\n')
        print('IMPORTANTE:')
        print('  - Deixe a TV na tela inicial (home) antes de começar.')
        print('  - Cada ID é testado por 4 segundos.')
        print('  - Olhe a TV e diga se o app abriu ou não.')
        print('  - Comandos: s = sim | n = não | q = parar\n')

        funcionaram = []

        for nome, app_id in CANDIDATOS:
            print(f'>>> Testando: {nome} (appId={app_id})')

            request = json.dumps({
                'method': 'ms.channel.emit',
                'params': {
                    'event': 'ed.apps.launch',
                    'to': 'host',
                    'data': {
                        'appId': app_id,
                        'action_type': 'DEEP_LINK',
                    },
                },
            })
            await ws.send(request)
            await asyncio.sleep(4)

            resposta = input(f'    {nome} abriu? (s/n/q): ').strip().lower()

            if resposta == 's':
                funcionaram.append((nome, app_id))
                print('    ✓ salvo')
            elif resposta == 'q':
                print('    parando...')
                break

            print()

        print()
        print('=' * 60)
        print('RESUMO — appIds que funcionaram:')
        print('=' * 60)
        if funcionaram:
            for nome, app_id in funcionaram:
                print(f"  '{nome}': '{app_id}',")
        else:
            print('  (nenhum)')
        print('=' * 60)


if __name__ == '__main__':
    try:
        asyncio.run(testar_todos())
    except KeyboardInterrupt:
        print('\nCtrl+C — encerrando.')