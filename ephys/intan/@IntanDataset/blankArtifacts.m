function X = blankArtifacts(obj, X, mask, opts)
%blankArtifacts  Replace artifact samples in [nSamples x nChan] data.
%   Y = ds.blankArtifacts(X, MASK) sets the rows of X flagged by the logical
%   MASK (as returned by detectArtifacts) to zero on every channel.
%
%   Y = ds.blankArtifacts(X, MASK, opts) with:
%     Fill   "zero" | "hold" | "nan"   (default "zero")
%            "zero" set flagged samples to 0
%            "hold" hold the last clean sample value across each flagged run
%            "nan"  set flagged samples to NaN (caller must handle before int16)
%
%   The mask length must equal size(X,1).
%
%   See also IntanDataset.detectArtifacts.

arguments
    obj (1,1) IntanDataset %#ok<INUSA>
    X double
    mask (:,1) logical
    opts.Fill (1,1) string {mustBeMember(opts.Fill, ["zero","hold","nan"])} = "zero"
end

if numel(mask) ~= size(X, 1)
    error('IntanDataset:blankArtifacts:SizeMismatch', ...
        'mask length (%d) must equal size(X,1) (%d).', numel(mask), size(X, 1));
end

if ~any(mask)
    return
end

switch opts.Fill
    case "zero"
        X(mask, :) = 0;
    case "nan"
        X(mask, :) = NaN;
    case "hold"
        % For each flagged run, hold the last clean sample (0 if run starts at 1)
        d = diff([0; mask; 0]);
        on  = find(d == 1);
        off = find(d == -1) - 1;
        for k = 1:numel(on)
            if on(k) > 1
                X(on(k):off(k), :) = repmat(X(on(k)-1, :), off(k)-on(k)+1, 1);
            else
                X(on(k):off(k), :) = 0;
            end
        end
end
end
