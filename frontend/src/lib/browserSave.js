// Open the picker in the original click, before fetching. Writing through the
// browser avoids handing a page-local blob: URL to an external download manager.
export async function saveBrowserFile(filename, readBlob) {
  let handle;
  if (typeof window.showSaveFilePicker === "function") {
    try {
      handle = await window.showSaveFilePicker({ suggestedName: filename });
    } catch (error) {
      if (error?.name === "AbortError") return "cancelled";
      if (!["SecurityError", "NotAllowedError", "NotSupportedError"].includes(error?.name)) throw error;
    }
  }
  const blob = await readBlob();
  if (handle) {
    const writer = await handle.createWritable();
    try {
      await writer.write(blob);
      await writer.close();
    } catch (error) {
      await writer.abort().catch(() => {});
      throw error;
    }
    return "saved";
  }
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
  return "requested";
}
