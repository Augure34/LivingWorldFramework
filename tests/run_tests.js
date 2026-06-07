const { LuaFactory } = require('wasmoon');
const fs = require('fs');
const path = require('path');

async function run() {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();
    
    // Redirect Lua print statements to the Node.js console
    lua.global.set('print', (...args) => console.log(...args));
    
    // Cache of loaded modules to match Lua standard require behavior
    const loadedModules = {};
    
    // Custom Lua require mapping to resolve local Lua files within the project workspace
    lua.global.set('require', (modulePath) => {
        if (loadedModules[modulePath]) {
            return loadedModules[modulePath];
        }
        
        // Translate lua require format (dots) to file path (slashes)
        let file = modulePath.replace(/\./g, '/') + '.lua';
        
        // Resolve path based on workspace location
        if (file.startsWith('LivingWorldFramework/')) {
            // Strip the framework prefix since this is running from the LWF repository
            file = file.substring('LivingWorldFramework/'.length);
        } else if (file.startsWith('TheFogDescend/') || file.startsWith('ColdSnap/')) {
            // Redirect to fixtures directory
            file = 'tests/fixtures/' + file;
        }
        
        // Always resolve relative to the repository root (one level up from this script's directory)
        const repoRoot = path.resolve(__dirname, '..');
        const resolvedPath = path.resolve(repoRoot, file);
        
        if (!fs.existsSync(resolvedPath)) {
            throw new Error(`[JS require mock] Module not found: ${modulePath} (resolved as: ${resolvedPath})`);
        }
        
        const content = fs.readFileSync(resolvedPath, 'utf-8');
        const result = lua.doStringSync(content);
        
        // If the module returns a value (e.g. a table), save it. Otherwise default to true.
        loadedModules[modulePath] = result !== undefined ? result : true;
        return loadedModules[modulePath];
    });
    
    // Expose standard Lua os.exit via Node process.exit
    lua.global.set('os', {
        exit: (code) => {
            process.exit(code);
        }
    });

    try {
        const testScriptPath = path.resolve(__dirname, 'test_scheduler.lua');
        const testScript = fs.readFileSync(testScriptPath, 'utf-8');
        await lua.doString(testScript);
    } catch (err) {
        console.error("Test execution failed with error:\n", err.message || err);
        process.exit(1);
    }
}

run();
