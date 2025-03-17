function hash = md5(filename)
%MD5 Compute the MD5 hash of a file.
%   HASH = MD5(FILENAME) computes the MD5 hash of the file specified
%   by FILENAME and returns it as a string of hexadecimal characters.
%
%   Input:
%       FILENAME - A string specifying the path to the file.
%
%   Output:
%       HASH - A string containing the MD5 hash in hexadecimal format.
%
%   Example:
%       hash = md5('example.txt');
%
%   Notes:
%   - This function uses Java's MessageDigest class to compute the MD5 hash.
%   - The file is read as raw bytes ('rb' mode) to ensure proper hashing.
%   - The function employs a persistent variable to reuse the
%     MessageDigest instance for efficiency.


fid = fopen(filename, 'rb');
if fid == -1
    error('MD5:FileOpenError', 'Cannot open file: %s', filename);
end
bytes = fread(fid, inf, 'uint8');
fclose(fid);

md = java.security.MessageDigest.getInstance('MD5');
hash = md.digest(bytes);

% Convert to hex string
hashString = dec2hex(typecast(hash, 'uint8'))';
hash = hashString(:)';
hash = string(hash);
