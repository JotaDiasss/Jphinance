# Jphinance

Aplicativo pessoal de finanças em SwiftUI para macOS 13 ou superior. Inclui orçamento, agenda, gastos mensais, metas e caixinhas.

## Estrutura

- `Sources/`: código SwiftUI do aplicativo.
- `Jphinance-1.0.zip`: pacote distribuído do app macOS, com ícone, iniciador e uma cópia das fontes usadas pelo iniciador.
- `docs/estrutura.md`: responsabilidades dos arquivos e cuidados para atualizar o pacote.

## Executar

Baixe e descompacte `Jphinance-1.0.zip`. Abra `Jphinance.app` em um Mac com compilador Swift e SDK do macOS instalados. Na primeira execução, o iniciador compila as fontes incluídas em `Jphinance.app/Contents/Resources/Sources`.

O app funciona localmente. Para habilitar a sincronização, configure `JphinanceSyncHost` em `Contents/Resources/NativeInfo.plist` com o domínio do serviço. Não coloque links privados, chaves ou dados financeiros no repositório.

O aplicativo para iPhone é mantido em [Jphinance-PWA](https://github.com/JotaDiasss/Jphinance-PWA).
