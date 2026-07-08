/**
 * Free-text fields (homework task/subject, schedule/timelog labels) get written
 * into `|`-delimited table rows. An unescaped `|` or newline in user input shifts
 * every subsequent column on reparse, silently corrupting that row. Swap them for
 * lookalike characters that render fine but can't be mistaken for the delimiter.
 */
export function sanitizeCell(value: string): string {
  return value.replace(/\|/g, '❘').replace(/\r?\n/g, ' ');
}

/**
 * Parse markdown tables into arrays of objects.
 * Handles tables with | delimiters, skips separator rows with dashes.
 */
export function parseMarkdownTable(content: string): Record<string, string>[] {
  const lines = content.split('\n');
  let headerLine: string | null = null;
  let headers: string[] = [];
  const rows: Record<string, string>[] = [];

  for (const line of lines) {
    // Skip empty lines
    if (!line.trim()) continue;

    // Skip non-table lines (don't start with |)
    if (!line.trim().startsWith('|')) continue;

    // Extract cells from the line
    const cells = line
      .split('|')
      .slice(1, -1) // Remove leading/trailing empty strings
      .map(cell => cell.trim());

    // Check if this is a separator row (all cells contain dashes)
    const isSeparator = cells.every(cell => /^-+$/.test(cell) || /^:-+:?$/.test(cell) || /^:-+$/.test(cell) || /^-+:$/.test(cell));

    if (isSeparator) {
      // Skip separator rows
      continue;
    }

    if (!headerLine) {
      // First table row is the header
      headerLine = line;
      headers = cells;
    } else {
      // Data row
      const row: Record<string, string> = {};
      cells.forEach((cell, idx) => {
        const header = headers[idx] || `col_${idx}`;
        row[header] = cell;
      });
      rows.push(row);
    }
  }

  return rows;
}

/**
 * Extract sections from markdown content.
 * Returns array of { title, content } for each ## heading and its content.
 */
export function extractSections(content: string): Array<{ title: string; content: string }> {
  const sections: Array<{ title: string; content: string }> = [];
  const lines = content.split('\n');
  let currentTitle = '';
  let currentContent: string[] = [];

  for (const line of lines) {
    if (line.startsWith('## ')) {
      // Save previous section
      if (currentTitle) {
        sections.push({
          title: currentTitle,
          content: currentContent.join('\n')
        });
      }
      currentTitle = line.replace(/^## /, '').trim();
      currentContent = [];
    } else {
      currentContent.push(line);
    }
  }

  // Save last section
  if (currentTitle) {
    sections.push({
      title: currentTitle,
      content: currentContent.join('\n')
    });
  }

  return sections;
}

/**
 * Parse the universal block types table to get duration ranges by block name.
 */
export function extractUniversalBlockTypes(content: string): Record<string, string> {
  const blockMap: Record<string, string> = {};
  const lines = content.split('\n');
  let inUniversalBlock = false;
  const universalBlockLines: string[] = [];

  // Find and collect Universal Block Types table
  for (const line of lines) {
    if (line.includes('Universal Block Types')) {
      inUniversalBlock = true;
      continue;
    }
    if (inUniversalBlock) {
      if (line.startsWith('## ')) {
        // Hit next section, stop collecting
        break;
      }
      universalBlockLines.push(line);
    }
  }

  // Parse the table
  const tableContent = universalBlockLines.join('\n');
  const rows = parseMarkdownTable(tableContent);

  for (const row of rows) {
    const blockName = row['Block'] || row['block'];
    const duration = row['Duration'] || row['duration'];
    if (blockName && duration) {
      blockMap[blockName.trim()] = duration.trim();
    }
  }

  return blockMap;
}

/**
 * Extract fields from embedded text like "Source: ... Output: ... Benchmark: ..."
 */
export function parseEmbeddedFields(text: string): {
  source: string;
  action: string;
  output: string;
  benchmark: string;
} {
  const result = {
    source: '',
    action: '',
    output: '',
    benchmark: ''
  };

  const sourceMatch = text.match(/Source:\s*([^.]+(?:\.|(?=[A-Z]|$))|[^.]+)/i);
  if (sourceMatch) {
    result.source = sourceMatch[1].trim().replace(/\.$/, '');
  }

  const actionMatch = text.match(/Action:\s*([^.]+(?:\.|(?=[A-Z]|$))|[^.]+)/i);
  if (actionMatch) {
    result.action = actionMatch[1].trim().replace(/\.$/, '');
  }

  const outputMatch = text.match(/Output:\s*([^.]+(?:\.|(?=[A-Z]|$))|[^.]+)/i);
  if (outputMatch) {
    result.output = outputMatch[1].trim().replace(/\.$/, '');
  }

  const benchmarkMatch = text.match(/Benchmark:\s*([^.]+(?:\.|(?=[A-Z]|$))|[^.]+)/i);
  if (benchmarkMatch) {
    result.benchmark = benchmarkMatch[1].trim().replace(/\.$/, '');
  }

  // Text before the first recognized label is the free-form action/description
  // (e.g. "Solve NCERT exercise + 10 problems." before a trailing "Benchmark: ...").
  // Only fall back to this if no explicit "Action:" label already set it — never
  // dump the whole cell (including already-extracted label text) into a field.
  if (!result.action) {
    const firstLabelMatch = text.match(/\b(Source|Action|Output|Benchmark):/i);
    const leading = firstLabelMatch ? text.slice(0, firstLabelMatch.index).trim() : text.trim();
    result.action = leading;
  }

  return result;
}
