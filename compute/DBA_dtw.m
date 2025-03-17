function score = DBA_dtw(T,S)
% score = DBA_dtw(T,S)
% 
% Fast compute of dtw distance from DBA()

costM = zeros(length(S),length(T));
costM(1,1) = (S(1)-T(1))^2;

for i=2:length(S)
    costM(i,1)= costM(i-1,1)+ (S(i)-T(1))^2;
end
for i=2:length(T)
    costM(1,i)= costM(1,i-1)+ (S(1)-T(i))^2;
end
for i=2:length(S)
    for j=2:length(T)
        costM(i,j)=min(min(costM(i-1,j-1),costM(i,j-1)),costM(i-1,j))+(S(i)-T(j))^2;
    end
end
score = sqrt(costM(length(S),length(T)));
