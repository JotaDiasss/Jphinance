# Organização do projeto

Este repositório contém o código SwiftUI do aplicativo macOS e um pacote pronto para uso. O aplicativo do iPhone é mantido separadamente em [Jphinance-PWA](https://github.com/JotaDiasss/Jphinance-PWA).

## Código

| Arquivo | Responsabilidade |
| --- | --- |
| `JphinanceApp.swift` | Entrada do app, navegação e componentes gerais |
| `Ledger.swift` | Modelos, datas e regras dos lançamentos |
| `Store.swift` | Persistência e estado compartilhado |
| `Agenda.swift` | Calendário e relatórios |
| `EntryEditor.swift` | Formulários e validação |
| `Savings.swift` | Metas e caixinhas |

`Jphinance-1.0.zip` é um artefato de distribuição; o código compilado pelo iniciador está dentro de `Jphinance.app/Contents/Resources/Sources` no ZIP. Se alterar um dos arquivos Swift para uma nova versão, atualize também o pacote distribuído e teste a abertura do app. O ZIP pode estar em uma versão diferente dos arquivos Swift da raiz até que essa atualização seja feita.

## Sincronização

O Mac e o PWA são aplicativos distintos. O endereço do serviço é configurado no pacote Mac por `JphinanceSyncHost`; o PWA recebe o link de pareamento nos Ajustes. Chaves, dados financeiros e links privados não pertencem ao repositório.

## Próximos passos de estrutura

Ao transformar o app em um projeto Xcode com build reproduzível, mova os arquivos Swift para uma pasta `Sources/`, inclua os recursos no projeto e gere o pacote a partir dessa fonte única. Evite mover apenas os arquivos da raiz enquanto o ZIP ainda usa outra cópia.
