//
//  MangaDetailView.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 11/13/25.
//

import SwiftUI

struct MangaDetailView: View {
    let manga: Manga
    @StateObject private var vm: MangaDetailViewModel
    
    init(manga: Manga){
        self.manga = manga
        _vm = StateObject(wrappedValue: MangaDetailViewModel(manga: manga))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: manga.coverURL) { phase in switch phase {
                case .success(let img):
                    img.resizable().scaledToFit().frame(maxWidth: .infinity)
                case .empty:
                    Rectangle().fill(.gray.opacity(0.2))
                        .frame(height: 300)
                default:
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .frame(height: 300)
                    
                }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(manga.title)
                        .font(.largeTitle.bold())
                    
                    if !vm.authors.isEmpty {
                        Text(vm.authors.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .font(.headline)
                    }
                }
                .padding(.horizontal)
                
                if !vm.tags.isEmpty{
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(vm.tags, id: \.self) { tag in
                                Text(tag)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.title3.bold())
                    Text(vm.description)
                        .font(.body)
                }
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chapters")
                        .font(.title3.bold())
                    ForEach(vm.chapters) { chapter in NavigationLink {
                        ReaderView(chapterId: chapter.id)
                    } label: {
                        HStack {
                            Text("Ch. \(chapter.number) - \(chapter.title ?? "") ")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.load()
        }
    }
                        
                        

                    
                        
                    
                
                    
    }
