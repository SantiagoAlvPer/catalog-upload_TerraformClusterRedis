import * as esbuild  from "esbuild";

esbuild.build({
    entryPoints: ["src/handlers/*.ts"],
    minify: true,
    bundle: true,
    platform: 'node',
    outdir: "dist",
    outbase: "src",
    format: "cjs",
    tsconfig: "tsconfig.json",
    target:"node20.13.0",
    metafile: true,
}).then((result) => {
    console.log("Build completed successfully:", result);
    for (const [file, info] of Object.entries(result.metafile.outputs)) {
        const size = (info.bytes / 1024).toFixed(2);
        console.log(`File: ${file}, Size: ${size} KB`);
    }
}).catch((error) => {
    console.error("Build failed:", error);
});

