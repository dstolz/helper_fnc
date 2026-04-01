function percent = parfor_progress(N,note)
%PARFOR_PROGRESS Progress monitor (progress bar) that works with parfor.
%   PARFOR_PROGRESS works by creating a file called parfor_progress.txt in
%   a temporary directory, and then keeping track of the parfor loop's
%   progress within that file. This workaround is necessary because parfor
%   workers cannot communicate with one another so there is no simple way
%   to know which iterations have finished and which haven't.
%
%   PARFOR_PROGRESS(N) initializes the progress monitor for a set of N
%   upcoming calculations.
%
%   PARFOR_PROGRESS updates the progress inside your parfor loop and
%   displays an updated progress bar.
%
%   PARFOR_PROGRESS(0) deletes parfor_progress.txt and finalizes progress
%   bar.
%
%   To suppress output from any of these functions, just ask for a return
%   variable from the function calls, like PERCENT = PARFOR_PROGRESS which
%   returns the percentage of completion.
%
%   Example:
%
%      N = 100;
%      parfor_progress(N);
%      parfor i=1:N
%         pause(rand); % Replace with real code
%         parfor_progress;
%      end
%      parfor_progress(0);
%
%   See also PARFOR.
% By Jeremy Scheff - jdscheff@gmail.com - http://www.jeremyscheff.com/

arguments
    N = -1
    note = []
end

narginchk(0, 2);

percent = 0;
w = 50; % Width of progress bar

% Use system temporary directory (Windows 11: e.g., %TEMP%)
progfile = fullfile(tempdir, 'parfor_progress.txt');

if N > 0
    f = fopen(progfile, 'w');
    if f < 0
        error('Do you have write permissions for %s?', tempdir);
    end
    fprintf(f, '%d\n', N); % Save N at the top of progress.txt
    fclose(f);

    if nargin == 2 && ~isempty(note)
        fprintf('%s\t', note)
    end

    if nargout == 0
        disp(['  0%[>', repmat(' ', 1, w), ']']);
    end
elseif N == 0
    warning('off','MATLAB:DELETE:Permission')
    delete(progfile);
    percent = 100;
    warning('on','MATLAB:DELETE:Permission')
    if nargout == 0
        disp([repmat(char(8), 1, (w+8)), '100%[', repmat('=', 1, w+1), ']']);
    end
else
    if ~exist(progfile, 'file')
        error('parfor_progress.txt not found. Run PARFOR_PROGRESS(N) before PARFOR_PROGRESS to initialize parfor_progress.txt.');
    end

    f = fopen(progfile, 'a');
    fprintf(f, '1\n');
    fclose(f);

    f = fopen(progfile, 'r');
    progress = fscanf(f, '%d');
    fclose(f);

    percent = (length(progress)-1)/progress(1)*100;

    if nargout == 0
        p = round(percent*w/100);
        perc = sprintf('%3.0f%%', percent); % 4 characters wide, percentage
        disp([repmat(char(8), 1, (w+8)), perc, '[', repmat('=', 1, p), '>', repmat(' ', 1, w - p), ']']);
    end
end

if nargout == 0
    clear percent
end
