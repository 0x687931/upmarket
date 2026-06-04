const SUPPORTED_FILE_TYPES = [
    "pdf", "doc", "docx", "pptx", "xlsx", "html", "htm", "txt", "md", "rtf",
    "png", "jpg", "jpeg", "tif", "tiff", "webp", "csv"
];

exports.activate = function() {
    nova.commands.register("upmarket.convertCurrentFile", convertCurrentFile);
    nova.commands.register("upmarket.convertChosenFile", convertChosenFile);
    nova.commands.register("upmarket.insertConvertedFile", insertConvertedFile);
    nova.commands.register("upmarket.copyConvertedFile", copyConvertedFile);
};

function convertCurrentFile(context) {
    return withConversion(async () => {
        const inputPath = currentEditorPath(context);
        const markdown = await convert(inputPath);
        await nova.workspace.openNewTextDocument({ content: markdown });
        notify("Upmarket", "Converted Markdown opened in a new document.");
    });
}

function convertChosenFile() {
    return chooseInputFile(async (inputPath) => {
        await withConversion(async () => {
            const markdown = await convert(inputPath);
            await nova.workspace.openNewTextDocument({ content: markdown });
            notify("Upmarket", "Converted Markdown opened in a new document.");
        });
    });
}

function insertConvertedFile(context) {
    return chooseInputFile(async (inputPath) => {
        await withConversion(async () => {
            const editor = activeEditor(context);
            if (!editor) {
                throw new Error("Open a text editor before inserting converted Markdown.");
            }
            const markdown = await convert(inputPath);
            await editor.insert(markdown);
            notify("Upmarket", "Converted Markdown inserted.");
        });
    });
}

function copyConvertedFile() {
    return chooseInputFile(async (inputPath) => {
        await withConversion(async () => {
            const markdown = await convert(inputPath);
            await nova.clipboard.writeText(markdown);
            notify("Upmarket", "Converted Markdown copied.");
        });
    });
}

async function withConversion(operation) {
    try {
        await operation();
    } catch (error) {
        showError(error.message || "Conversion failed.");
    }
}

function currentEditorPath(context) {
    const editor = activeEditor(context);
    if (!editor || !editor.document || !editor.document.path) {
        throw new Error("Open a saved file before converting.");
    }
    return editor.document.path;
}

function activeEditor(context) {
    if (typeof TextEditor !== "undefined" && TextEditor.isTextEditor(context)) {
        return context;
    }
    return nova.workspace.activeTextEditor;
}

function chooseInputFile(callback) {
    nova.workspace.showFileChooser(
        "Choose a document to convert.",
        {
            prompt: "Convert",
            allowFiles: true,
            allowFolders: false,
            allowMultiple: false,
            filetype: SUPPORTED_FILE_TYPES
        },
        (paths) => {
            if (!paths || paths.length === 0) {
                return;
            }
            callback(paths[0]);
        }
    );
}

function convert(inputPath) {
    const cliPath = nova.config.get("upmarket.cliPath") || "/usr/local/bin/upmarket";
    const outputMode = nova.config.get("upmarket.outputMode") || "markdown";
    const extension = outputMode === "json" ? "json" : "md";
    const outputPath = nova.path.join(
        nova.fs.tempdir,
        `upmarket-nova-${Date.now()}-${Math.floor(Math.random() * 1000000)}.${extension}`
    );
    const args = ["convert", inputPath, "-o", outputPath, "--force", "--format", outputMode];
    if (nova.config.get("upmarket.useAI")) {
        args.push("--ai");
    }

    return runProcess(cliPath, args)
        .then(() => readTextFile(outputPath))
        .finally(() => removeQuietly(outputPath));
}

function runProcess(command, args) {
    return new Promise((resolve, reject) => {
        const process = new Process(command, {
            args,
            stdio: "pipe"
        });
        const stdout = [];
        const stderr = [];

        process.onStdout((line) => stdout.push(line));
        process.onStderr((line) => stderr.push(line));
        process.onDidExit((status) => {
            if (status === 0) {
                resolve();
                return;
            }
            reject(new Error(errorMessageForStatus(status, stderr.concat(stdout).join("\n"))));
        });

        try {
            process.start();
        } catch (error) {
            reject(new Error("Install the Upmarket command line tool or update its path in Extension Settings."));
        }
    });
}

function readTextFile(path) {
    const file = nova.fs.open(path, "r", "utf8");
    try {
        return file.read();
    } finally {
        file.close();
    }
}

function removeQuietly(path) {
    try {
        nova.fs.remove(path);
    } catch (_) {
        // Temporary-output cleanup should not replace the conversion result.
    }
}

function errorMessageForStatus(status, detail) {
    switch (status) {
    case 2:
        return "Upmarket could not read that file.";
    case 3:
        return "Upmarket needs a license or document credit for this conversion.";
    case 4:
        return "Upmarket AI is not available for this conversion.";
    case 5:
        return "Conversion failed.";
    case 6:
        return "Upmarket could not write the converted Markdown.";
    default:
        return scrubDetail(detail) || "Conversion failed.";
    }
}

function scrubDetail(detail) {
    if (!detail) {
        return "";
    }
    return detail
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line && !line.includes("/"))
        .slice(-1)[0] || "";
}

function notify(title, body) {
    const request = new NotificationRequest("upmarket-conversion");
    request.title = title;
    request.body = body;
    nova.notifications.add(request);
}

function showError(message) {
    if (nova.workspace && nova.workspace.showErrorMessage) {
        nova.workspace.showErrorMessage(message);
        return;
    }

    const request = new NotificationRequest("upmarket-error");
    request.title = "Upmarket";
    request.body = message;
    nova.notifications.add(request);
}
