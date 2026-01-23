const startPage = dv.current().file.path;
const direct = [];
const indirect = [];
const visited = new Set();

async function crawl(pagePath, depth = 0) {
    if (visited.has(pagePath)) return;
    visited.add(pagePath);
    
    const page = dv.page(pagePath);
    if (!page) return;

    if (page.file.path !== startPage) {
        // We store the 'name' separately for the secondary sort
        const rowData = {
            link: page.file.link,
            name: page.file.name,
            type: page.type || "N/A"
        };
        
        if (depth === 1) direct.push(rowData);
        else if (depth > 1) indirect.push(rowData);
    }

    const children = dv.array(page.down);
    for (const child of children) {
        if (child?.path) await crawl(child.path, depth + 1);
    }
}

await crawl(startPage);

// --- Multi-Level Sorting Function ---
// Sorts by Type (index 0) then Name (index 1)
const multiSort = (a, b) => {
    // 1. Primary Sort: Type
    const typeComp = a.type.localeCompare(b.type);
    if (typeComp !== 0) return typeComp;

    // 2. Secondary Sort: Name (if types are equal)
    return a.name.localeCompare(b.name);
};

// Map objects back to Table-friendly Arrays [Link, Type]
const formatRows = (rows) => rows.sort(multiSort).map(r => [r.link, r.type]);

// --- Render Tables ---
dv.header(3, "Direct Dependencies");
if (direct.length > 0) dv.table(["File", "Type"], formatRows(direct));
else dv.paragraph("No direct dependencies found.");

dv.header(3, "Indirect Dependencies");
if (indirect.length > 0) dv.table(["File", "Type"], formatRows(indirect));
else dv.paragraph("No indirect dependencies found.");
