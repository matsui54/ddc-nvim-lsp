import {
  BaseSource,
  Candidate,
  Context,
  DdcOptions,
  SourceOptions,
} from "https://deno.land/x/ddc_vim@v0.0.12/types.ts#^";
import {
  batch,
  Denops,
  vars,
} from "https://deno.land/x/ddc_vim@v0.0.12/deps.ts#^";
import { once } from "https://deno.land/x/denops_std@v1.0.1/anonymous/mod.ts";

const LSP_KINDS = [
  "Text",
  "Method",
  "Function",
  "Constructor",
  "Field",
  "Variable",
  "Class",
  "Interface",
  "Module",
  "Property",
  "Unit",
  "Value",
  "Enum",
  "Keyword",
  "Snippet",
  "Color",
  "File",
  "Reference",
  "Folder",
  "EnumMember",
  "Constant",
  "Struct",
  "Event",
  "Operator",
  "TypeParameter",
];

const LSP_KINDS_WITH_ICONS = [
  " [text]     ",
  " [method]   ",
  " [function] ",
  " [constructor]",
  "ﰠ [field]    ",
  "𝒙 [variable] ",
  " [class]    ",
  " [interface]",
  " [module]   ",
  " [property] ",
  " [unit]     ",
  " [value]    ",
  " [enum]     ",
  " [key]      ",
  "﬌ [snippet]  ",
  " [color]    ",
  " [file]     ",
  " [refrence] ",
  " [folder]   ",
  " [enumMember]",
  " [constant] ",
  " [struct]   ",
  " [event]    ",
  " [operator] ",
  " [typeParameter]",
];

type Params = {
  useIcon: boolean;
};

export class Source extends BaseSource {
  async onInit(
    denops: Denops,
  ): Promise<void> {
    await batch(denops, (helper) => {
      vars.g.set(helper, "ddc#source#lsp#_results", []);
    });
  }

  async gatherCandidates(
    denops: Denops,
    context: Context,
    _ddcOptions: DdcOptions,
    _sourceOptions: SourceOptions,
    sourceParams: Record<string, Params>,
    completeStr: string,
  ): Promise<Candidate[]> {
    const params = await denops.call(
      "luaeval",
      "vim.lsp.util.make_position_params()",
    );

    return new Promise((resolve) => {
      denops.call(
        "luaeval",
        "require('ddc_nvim_lsp').request_candidates(_A.params, _A.callback)",
        {
          "params": params,
          "callback": once(denops, async (response) => {
            if (response == "1") {
              const results = await vars.g.get(
                denops,
                "ddc#source#lsp#_results",
                [],
              );
              return resolve(
                this.processCandidates(
                  results,
                  sourceParams,
                  context.input,
                  context.input.length - completeStr.length,
                ),
              );
            }
            return resolve([]);
          })[0],
        },
      );
    }).then((cs: Candidate[]) => {
      return cs;
    });
  }

  async processCandidates(
    results: Record<string, unknown>,
    params: Params,
    input: string,
    position: number,
  ): Promise<Candidate[]> {
    if (results.length == 0) {
      return [];
    }

    const candidates = results.map((v) => {
      let word = "";

      if ("textEdit" in v && v["textEdit"]) {
        const textEdit = v["textEdit"];
        if ("range" in textEdit && textEdit.range.start == textEdit.range.end) {
          word = `${input.slice(position)}${textEdit.newText}`;
        } else {
          word = textEdit.newText;
        }
      } else if ("insertText" in v) {
        if ("insertText" in v && v.insertTextFormat != 1) {
          word = "entryName" in v ? v.entryName : v.label;
        } else {
          word = v.insertText;
        }
      } else {
        word = "entryName" in v ? v.entryName : v.label;
      }

      // Remove parentheses from word.
      // Note: some LSP includes snippet parentheses in word(newText)
      word = word.replace(/[\(|<].*[\)|>](\$\d+)?/, "");

      const item = {
        word: word,
        abbr: v.label,
        dup: 0,
        "user_data": JSON.stringify({
          lspitem: v,
        }),
      };

      if (typeof v.kind === "number") {
        item.kind = params.useIcon
          ? LSP_KINDS_WITH_ICONS[v.kind - 1]
          : LSP_KINDS[v.kind - 1];
      } else if (v.insertTextFormat && v.insertTextFormat == 2) {
        item.kind = "Snippet";
      }

      if (v.detail) {
        item.menu = v.detail;
      }

      if (typeof v.documentation === "string") {
        item.info = v.documentation;
      } else if (v.documentation && "value" in v.documentation) {
        item.info = v.documentation.value;
      }

      return item;
    });

    return candidates;
  }

  params(): Record<string, unknown> {
    const params: Params = {
      useIcon: false,
    };
    return params as unknown as Record<string, unknown>;
  }
}
