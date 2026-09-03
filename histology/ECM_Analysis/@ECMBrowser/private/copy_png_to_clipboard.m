function copy_png_to_clipboard(file)
%COPY_PNG_TO_CLIPBOARD Put one PNG file on the Windows clipboard.
% Under both names an application might ask for it by: PNG, and bitmap.
% The bytes go over as they were written rather than encoded a second
% time, so what comes out of a paste is the file that went in.

NET.addAssembly("System.Windows.Forms");
NET.addAssembly("System.Drawing");

fid = fopen(file, "r");

if fid < 0
    error("ECMBrowser:clipboardRead", ...
        "Could not read the plot back from %s.", file)
end

closeWhenDone = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");

% Two streams rather than one read twice: GDI+ reads the image out of the
% stream it was handed as it needs it, so the stream behind the bitmap has
% to stay open and at its own position until the clipboard is written.
pngStream = System.IO.MemoryStream(bytes);
bitmapStream = System.IO.MemoryStream(bytes);

data = System.Windows.Forms.DataObject();
data.SetData("PNG", pngStream);
data.SetData(System.Windows.Forms.DataFormats.Bitmap, ...
    System.Drawing.Image.FromStream(bitmapStream));

% Given rather than promised: the picture stays on the clipboard after the
% browser that put it there has closed.
System.Windows.Forms.Clipboard.SetDataObject(data, true);

end
