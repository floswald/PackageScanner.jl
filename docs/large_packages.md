# Handling Large Packages

PackageScanner now supports **selective extraction** for very large replication packages. This feature allows you to:

- Create a complete file manifest of ALL files in the package
- Extract and analyze only files below a size threshold
- Keep track of which files were checked vs. catalogued only
- Generate reports showing complete coverage with extraction status

## Problem

Some replication packages can be extremely large (tens of GB), often containing:
- Large video files
- Big binary datasets
- High-resolution images
- Raw data dumps

Extracting everything can be impractical due to:
- Disk space constraints
- Processing time
- Memory limitations

## Solution

The new workflow allows you to:

1. **Inspect** the package without extracting it
2. **Choose** a size threshold (default: 2GB per file)
3. **Extract** only files below the threshold
4. **Maintain** complete file manifest (all files catalogued)
5. **Track** which files were checked vs. skipped

## Usage

### Basic Workflow

```julia
using PackageScanner

# For a zip file
pkg_dir, manifest = prepare_package_for_precheck("large_package.zip")
precheck_package(pkg_dir, pre_manifest=manifest)

# For an already-extracted directory
pkg_dir, manifest = prepare_package_for_precheck("/path/to/large/package")
precheck_package(pkg_dir, pre_manifest=manifest)
```

### Interactive Mode (Default)

When you run with a large package, you'll see:

```
============================================================
LARGE PACKAGE DETECTED
============================================================
Full size of zip: 45.3 GB

Default: extract all files smaller than 2.0 GB
OK? (y/n): y
Using default threshold: 2.0 GB
============================================================

Extracting 234 files...
```

If you answer `n`, you'll be prompted to enter a custom threshold:

```
OK? (y/n): n
Enter size threshold in GB: 5.0
Using threshold: 5.0 GB
```

### Non-Interactive Mode

For automated workflows:

```julia
# Use default 2GB threshold
pkg_dir, manifest = prepare_package_for_precheck(
    "package.zip",
    interactive=false
)

# Use custom threshold
pkg_dir, manifest = prepare_package_for_precheck(
    "package.zip",
    size_threshold_gb=5.0,
    interactive=false
)
```

## What Gets Generated

### 1. Extraction Summary Report

A new report `report-extraction-summary.md` is created showing:

- Total files in package
- Files extracted and checked
- Files catalogued but not checked
- Size breakdown
- List of skipped files with sizes and reasons

Example:

```markdown
## Extraction Summary

This package was processed with **selective extraction** due to its large size.

**Package Statistics:**

- Total files in package: **1,247**
- Files extracted and checked: **1,189**
- Files catalogued but not checked: **58**
- Total package size: **47.23 GB**
- Size extracted: **8.45 GB**
- Size not extracted: **38.78 GB**

### Files Not Extracted

| File | Size (GB) | Reason |
|:-----|----------:|:-------|
| data/raw/video_recordings.mp4 | 15.30 | Exceeds threshold |
| data/raw/satellite_images.zip | 12.45 | Exceeds threshold |
...
```

### 2. Updated File Classification Reports

Classification files now show both checked and unchecked files:

**program-files.txt:**
```
✓ /code/analysis.R [checked]
✓ /code/clean_data.py [checked]
⊘ /code/large_simulation.jl [not_extracted: 3.5GB]
```

**data-files.md:**
```
✓ /data/survey_responses.csv [checked]
✓ /data/demographics.dta [checked]

# Files not extracted (catalogued only):
⊘ /data/raw_satellite_data.hdf [not_extracted: 25.30GB]
⊘ /data/video_observations.mp4 [not_extracted: 10.20GB]
```

### 3. Complete File Manifest

The file manifest (`report-file-sizes.md`) includes ALL files with their metadata, even those not extracted.

## How It Works

### For Zip Files

1. **Inspection Phase**: Uses `ZipFile.jl` to read zip metadata WITHOUT extraction
2. **Manifest Creation**: Builds complete file list with sizes from zip headers
3. **Filtering**: Applies size threshold to decide what to extract
4. **Selective Extraction**: Uses `unzip` with file list to extract only selected files
5. **Tracking**: Marks which files were extracted in the manifest

### For Directories

1. **Scanning Phase**: Walks directory tree to catalog all files
2. **Manifest Creation**: Builds complete file list with actual file sizes
3. **Filtering**: Applies size threshold to mark which files to check
4. **Processing**: Only scans marked files during precheck
5. **Tracking**: Files remain on disk but are marked as "not checked" in reports

## Key Functions

### `prepare_package_for_precheck(input_path; kwargs...)`

Unified entry point that handles both zip files and directories.

**Arguments:**
- `input_path::String`: Path to zip file or directory
- `size_threshold_gb::Union{Nothing,Float64}`: Size threshold in GB (default: prompt or 2.0)
- `interactive::Bool`: Whether to prompt user (default: true)

**Returns:**
- `(package_directory, manifest)`: Tuple of extraction directory and complete manifest

### `create_manifest_from_zip(zip_path; kwargs...)`

Creates manifest and extracts selectively from zip file.

**Arguments:**
- `zip_path::String`: Path to zip file
- `size_threshold_gb::Union{Nothing,Float64}`: Size threshold
- `interactive::Bool`: Whether to prompt

**Returns:**
- `(manifest, extract_dir)`: Tuple of manifest DataFrame and extraction directory

### `create_manifest_from_directory(dir_path; kwargs...)`

Creates manifest from existing directory and marks files for checking.

**Arguments:**
- `dir_path::String`: Path to directory
- `size_threshold_gb::Union{Nothing,Float64}`: Size threshold
- `interactive::Bool`: Whether to prompt

**Returns:**
- `manifest`: DataFrame with all files and check status

## Manifest Structure

The manifest DataFrame has these columns:

- `filepath`: Relative path of the file
- `size_bytes`: File size in bytes
- `size_gb`: File size in GB
- `compressed_size`: Compressed size (zip only)
- `crc32` or `checksum`: File hash (CRC32 for zip, SHA1 for extracted)
- `extracted`: Boolean - was this file extracted?
- `checked`: Boolean - was this file scanned for PII, etc.?

## Backward Compatibility

The existing workflow continues to work without changes:

```julia
# Original workflow - extracts everything
read_and_unzip_directory(dir_path)
precheck_package("replication-package")
```

The new parameters are all optional with sensible defaults, so existing code continues to work.

## Best Practices

1. **Start with defaults**: The 2GB threshold works well for most cases
2. **Check the summary**: Review `report-extraction-summary.md` to see what was skipped
3. **Adjust if needed**: Re-run with different threshold if too much was skipped
4. **Document decisions**: Note in your report why certain files weren't checked
5. **Consider file types**: Code and documentation should always be checked; large data files can often be skipped

## Example Workflow

```julia
using PackageScanner

# Step 1: Prepare package with selective extraction
pkg_dir, manifest = prepare_package_for_precheck(
    "/path/to/large_package.zip",
    size_threshold_gb=2.0,  # 2GB per file
    interactive=true
)

# Step 2: Run precheck with manifest
precheck_package(pkg_dir, pre_manifest=manifest)

# Step 3: Review reports
# - Check report-extraction-summary.md for what was skipped
# - Review program-files.txt to see all code files (checked + catalogued)
# - Review data-files.md to see all data files (checked + catalogued)

# Step 4: If needed, adjust threshold and re-run
pkg_dir2, manifest2 = prepare_package_for_precheck(
    "/path/to/large_package.zip",
    size_threshold_gb=5.0,  # Increase to 5GB
    interactive=false
)
precheck_package(pkg_dir2, pre_manifest=manifest2)
```

## Limitations

- Only individual file size is considered (not total package size)
- No content-based filtering (e.g., can't skip by file type)
- Files must be under threshold to be checked at all (no partial file scanning)
- Checksums for non-extracted zip files use CRC32 (from zip), not SHA1

## Future Enhancements

Potential future improvements could include:

- Total extraction size limits (stop after extracting X GB total)
- Content-based filtering (skip certain extensions)
- Sampling large files (extract first N MB for inspection)
- Parallel extraction and processing
- Progress bars for long operations
